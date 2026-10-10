package Munin::Master::Update;


use warnings;
use strict;

use English qw(-no_match_vars);
use Carp;

use Time::HiRes;
use Munin::Common::Logger;
use List::Util qw( shuffle );

use Munin::Common::Defaults;
use Munin::Master::Config;
use Munin::Master::Schema;
use Munin::Master::UpdateWorker;
use Munin::Master::Utils;
use Munin::Master::Limits;

my $config_old;
my $config = Munin::Master::Config->instance()->{config};
$config->{version} = $Munin::Common::Defaults::MUNIN_VERSION;


sub new {
    my ($class) = @_;

    my $self = bless {
        old_service_configs => {},
        old_version         => undef,
        workers             => [],
        failed_workers      => [],
        config_dump_file    => "$config->{dbdir}/datafile",
    }, $class;
}


sub run {
    my ($self) = @_;

    $self->_create_rundir_if_missing();
    $self->{runid} = time();

    $self->_do_with_timing(sub {
        INFO "Starting munin-update";

	# Create the DB, using a local block to close the DB cnx
	{
		my $dbh = get_dbh();
		$self->_db_init($dbh);
		$config_old = $self->_db_params_update($dbh, $config);
	}

	# Import groups/hosts from config into SQL
	$self->_db_groups_update();

	# Build the worker list on an explicit handle, then close it: no
	# handle may be open when _run_workers forks.
	{
		my $work_dbh = get_dbh();
		$self->{workers} = $self->_create_workers($work_dbh);
		$work_dbh->disconnect();
	}
        my $nb_workers = $self->_run_workers();

	# Import contacts and config overrides into SQL
	$self->_db_import_config();

	# Run limits after update — evaluate thresholds and send notifications
	$self->_run_limits();

	return $nb_workers;
    });
}

# Evaluate thresholds and send notifications.
# Called at the end of update, so limits runs in the same process.
sub _run_limits {
    my ($self) = @_;

    INFO "Running limits (inline)";

    Munin::Master::Limits::limits_main();

    INFO "Limits finished";
}

# If you need a readonly DBH, use M::M::U::get_dbh("readonly").
sub get_dbh {
	my ($is_read_only) = @_;

	my $datafilename = $ENV{MUNIN_DBURL} || $config->{dburl} || "$config->{dbdir}/datafile.sqlite";
	my $db_driver = $ENV{MUNIN_DBDRIVER} || $config->{dbdriver};
	my $db_user = $ENV{MUNIN_DBUSER} || $config->{dbuser};
	my $db_passwd = $ENV{MUNIN_DBPASSWD} || $config->{dbpasswd};
	# Note that we should reconnect for _each_ update part, as sharing a $dbh when forking()
	# will bring unhappiness
	#
	# So, using a caching version has to be careful. And reopen it on each thread/subprocess.

	# Not being able to open the DB connection seems FATAL to me. Better
	# die loudly than injecting some misguided data
	use DBI;
	my %db_args;
	$db_args{ReadOnly} = 1 if $is_read_only;
	$db_args{RaiseError} = 1;

	use Carp;
	$db_args{HandleError} = sub { confess(shift) };

	my $dbh = DBI->connect("dbi:$db_driver:dbname=$datafilename", $db_user, $db_passwd, \%db_args) or die $DBI::errstr;

	DEBUG 'get_dbh: $dbh->{Driver}->{Name} = ' . $dbh->{Driver}->{Name} . ($is_read_only ? "(ro)" : "(rw)");

	# Sets some session vars

	# db_journal_mode is only set explicitely. Otherwise use the platform SQLite default
	my $db_journal_mode = $ENV{MUNIN_DB_JOURNAL_MODE} || $config->{db_journal_mode};
	if ($db_journal_mode) {
		$dbh->do("PRAGMA journal_mode=$db_journal_mode;") if $db_driver eq "SQLite";
		DEBUG "get_dbh: PRAGMA journal_mode=$db_journal_mode;" if $db_driver eq "SQLite";
	}

	my $db_synchronous_mode = $ENV{MUNIN_DB_SYNCHRONOUS_MODE} || $config->{db_synchronous_mode} || "OFF";
	$dbh->do("PRAGMA main.synchronous=$db_synchronous_mode;") if $db_driver eq "SQLite";
	DEBUG "get_dbh: PRAGMA main.synchronous=$db_synchronous_mode;" if $db_driver eq "SQLite";

	# Enforce FK constraints - SQLite defaults to off. Without this the
	# url/state FK columns are purely decorative. Must run outside a txn.
	# (the groups import in Update.pm deliberately runs its own conn with FK off)
	$dbh->do("PRAGMA foreign_keys=ON;") if $db_driver eq "SQLite";
	DEBUG "get_dbh: PRAGMA foreign_keys=ON;" if $db_driver eq "SQLite";

	# AutoCommit when readonly is a no-op anyway
	$dbh->{AutoCommit} = $ENV{MUNIN_DB_AUTOCOMMIT} || $config->{db_autocommit} || 0;
	$dbh->{AutoCommit} = 1 if $is_read_only;
	DEBUG "get_dbh: {AutoCommit} = " . $dbh->{AutoCommit};

	# Fail loudly on schema mismatch: verify() is the single runtime
	# gate, shared by every consumer (update, limits, html, graph,
	# static renderers) -- today only munin-update used to run
	# _db_init, the others would limp against a stale schema. There is
	# no heuristic or repair branch here: daemons never migrate, adopt
	# or guess; that is munin-upgrade-db's job alone. Memoized per
	# process -- one cheap query, handles are opened repeatedly, and
	# migration is offline by contract.
	Munin::Master::Schema::verify($dbh);

	# Plainly returns it, but do *not* put it in $self, as it will let Perl
	# do its GC properly and closing it when out of scope.
	return $dbh;
}

# Lookup helpers take an explicit handle (prescriptive): a phase opens one,
# threads it, and closes it before forking. No cached/global handle, no
# silent reconnects -- a missing handle is a programming error.
sub get_param {
	my ($param_name, $dbh) = @_;
	die "get_param: dbh required\n" unless $dbh;
	my $sql = 'SELECT value FROM param WHERE name = ?';
	my ($param_value) = $dbh->selectrow_array($sql, undef, ($param_name));
	return $param_value;
}

# Get all hosts from the DB with their attributes.
# Returns arrayref of Host objects loaded from DB.
# Host objects have get_full_path() using the stored path.
sub get_hosts {
	my ($dbh) = @_;
	die "get_hosts: dbh required\n" unless $dbh;

	my $sql = q{
		SELECT n.id, n.name, n.path, g.name as group_name
		FROM node n
		JOIN grp g ON g.id = n.grp_id
		ORDER BY n.name
	};

	my $sth = $dbh->prepare($sql);
	$sth->execute();

	my @hosts;
	while (my $row = $sth->fetchrow_hashref) {
		# Get all attributes for this node
		my $attr_sth = $dbh->prepare(
			'SELECT name, value FROM node_attr WHERE id = ?'
		);
		$attr_sth->execute($row->{id});

		while (my $attr = $attr_sth->fetchrow_hashref) {
			$row->{$attr->{name}} = $attr->{value};
		}

		# Convert numeric strings back
		$row->{port} = int($row->{port}) if defined $row->{port};
		$row->{update} = int($row->{update}) if defined $row->{update};
		$row->{update_priority} = int($row->{update_priority}) if defined $row->{update_priority};

		# Create Host object with stored path
		# Use a mock group that provides get_full_path via the stored path
		my $stored_path = $row->{path};
		my $mock_group = bless {
			group_name => $row->{group_name},
		}, 'Munin::Master::Group';

		my $host = Munin::Master::Host->new(
			$row->{name},
			$mock_group,
			$row
		);

		# Store path for get_full_path to use
		$host->{_db_path} = $stored_path;

		push @hosts, $host;
	}

	return \@hosts;
}

# Get a config override value from the config_override table.
# Looks up by (host_name, service_name, field_name, attr_name).
# Returns undef if not found.
sub get_override {
	my ($host_name, $service_name, $field_name, $attr_name, $dbh) = @_;
	die "get_override: dbh required\n" unless $dbh;

	# Try exact match first (field-level override)
	my ($value) = $dbh->selectrow_array(
		'SELECT value FROM config_override WHERE host_name = ? AND service_name = ? AND field_name = ? AND name = ?',
		undef, $host_name, $service_name // '', $field_name // '', $attr_name
	);

	return $value if defined $value;

	# Fall back to service-level override (empty field_name)
	if (defined $field_name && $field_name ne '') {
		($value) = $dbh->selectrow_array(
			'SELECT value FROM config_override WHERE host_name = ? AND service_name = ? AND field_name = ? AND name = ?',
			undef, $host_name, $service_name // '', '', $attr_name
		);
		return $value if defined $value;
	}

	# Fall back to host-level override (empty service and field)
	($value) = $dbh->selectrow_array(
		'SELECT value FROM config_override WHERE host_name = ? AND service_name = ? AND field_name = ? AND name = ?',
		undef, $host_name, '', '', $attr_name
	);

	return $value;
}

sub _create_rundir_if_missing {
    my ($self) = @_;

    # Use config singleton - needed before DB exists
    my $rundir = $config->{rundir};
    unless (-d $rundir) {
	mkdir $rundir, oct(700)
            or croak "Failed to create rundir (".$rundir."): $!";

    }
}


sub _create_workers {
    my ($self, $dbh) = @_;

    my @hosts = @{ get_hosts($dbh) };

    # Use user-defined ordering, slow hosts should run first for
    # better global throughput, keep shuffle() to shuffle hosts within
    # same update_order
    @hosts = shuffle(@hosts);
    @hosts = sort { $a->{update_priority} <=> $b->{update_priority} } @hosts;

    my $limit_hosts = get_param('limit_hosts', $dbh);
    if (defined $limit_hosts && %{$limit_hosts}) {
        @hosts = grep { $limit_hosts->{$_->{name}} } @hosts
    }

    # Only create the "update yes" hosts
    @hosts = grep { $_->{update} } @hosts;

    return [ map { Munin::Master::UpdateWorker->new($_) } @hosts ];
}


sub _do_with_timing {
    my ($self, $block) = @_;

    my $start_time = Time::HiRes::time;
    # Place global munin-update timeout here.
    my $retval = $block->();

    my $update_time = Time::HiRes::time - $start_time;

    # Store the timings in the DB
    $self->_db_stats('UT', "", 	$update_time);

    my $update_time_string = sprintf("%.2f", $update_time);
    INFO "Munin-update finished ($update_time sec)";

    return $retval;
}

sub _db_stats {
	my ($self, $type, $name, $duration) = @_;

	my $runid = $self->{runid};
	my $dbh = $self->{dbh} || get_dbh(); # Reuse any existing connection, or open a temporary one
	my $dbh_driver = $dbh->{Driver}->{Name};
	my $sql_to_timestamp = "";
	$sql_to_timestamp = "TO_TIMESTAMP" if $dbh_driver eq "Pg";
	my $sth_i = $dbh->prepare_cached("INSERT INTO stats (runid, tstp, type, name, duration) VALUES (?, $sql_to_timestamp(?), ?, ?, ?);");
	$sth_i->execute($runid, time(), $type, $name, $duration);
	if ($type eq 'UT') {
		# One day retention policy
		my $sth_d= $dbh->prepare_cached("DELETE FROM stats where tstp < $sql_to_timestamp(?)");
		$sth_d->execute(time() - 86400);
		# Only retain last stats
		#my $sth_d= $dbh->prepare_cached("DELETE FROM stats where runid < ?");
		#$sth_d->execute($runid);
	}

	$dbh->commit();
}


sub _run_workers {
	my ($self) = @_;

	use Parallel::ForkManager;

	# Params are read on an explicit handle, closed before WORKER_LOOP:
	# fork() must see no open handle.
	my $dbh = get_dbh();
	my $max_processes = get_param('max_processes', $dbh) || 16;

	# Do NOT fork if not set
	$max_processes = 0 unless get_param('fork', $dbh);
	$dbh->disconnect();

	my $pm = Parallel::ForkManager->new($max_processes);

	# Handle child process failures
	my $nb_workers_failed = 0;
	$pm->run_on_finish(
		sub {
			my ($pid, $exit_code) = @_;

			$exit_code = 0 unless defined $exit_code;
			INFO "run_on_finish(pid:$pid, exit_code:$exit_code)";

			$nb_workers_failed++ if $exit_code;
		}
	);

	WORKER_LOOP:
	for my $worker (@{$self->{workers}}) {
		my $worker_pid = $pm->start($worker);
		next WORKER_LOOP if $worker_pid;

		my $start_time = Time::HiRes::time;

		my $res;
		eval {
			# Inject the 2 dbh (meta + state)
			$worker->{dbh} = get_dbh();

			# do_work fails hard on a number of conditions
			$res = $worker->do_work();
		};

		$worker->{dbh}->disconnect();

		my $worker_id = $worker->{ID};
		if (! $res || $@) {
			# No res, something went wrong
			# Note that we handle connection failure same as other
			# failures. Since "do_connect()" fails only softly.
			INFO "no connection or EVAL_ERROR:$@";
			$pm->finish(1, [ $worker_id ] );
		}

		my $time_used = Time::HiRes::time - $start_time;
		$self->_handle_worker_result([$worker_id, $time_used]);
		$pm->finish(); # Return 0
	}

	$pm->wait_all_children;

	# Everything worked, return the number of workers OK
	my $nb_workers = scalar @{$self->{workers}};
	my $nb_workers_ok = $nb_workers - $nb_workers_failed;
	return $nb_workers_ok;
}

sub _handle_worker_result {
    my ($self, $res) = @_;

    if (!defined($res)) {
	# no result? problem
	FATAL("Handle_worker_result got handed a failed worker result");
    }

    my ($worker_id, $time_used)
        = ($res->[0], $res->[1],);

    my $update_time = sprintf("%.2f", $time_used);
    INFO "Munin-update finished for node $worker_id ($update_time sec)";
    $self->_db_stats("UD", $worker_id, $time_used);
}

sub _db_init {
	my ($self, $dbh) = @_;

	# Runtime schema code is deliberately minimal: bootstrap a virgin
	# database, or verify the version and die. All migration logic --
	# the state-columns, ds.deleted and ds_rrd blocks that used to live
	# here, plus the notification rename -- is offline in
	# munin-upgrade-db (Schema::migrate_v0_to_v1). The handle is the
	# truth about the driver: Schema renders the DDL per handle, so
	# _db_init may be handed any handle (the test fixture opens its
	# own).
	my $state = Munin::Master::Schema::detect($dbh);
	if ($state eq 'fresh') {
		Munin::Master::Schema::create_schema($dbh);
		Munin::Master::Schema::record($dbh,
			Munin::Master::Schema::CURRENT_SCHEMA_VERSION(),
			'bootstrap: full schema created');
	} elsif ($state eq 'unversioned') {
		die Munin::Master::Schema::mismatch_message($dbh, 'unversioned');
	} else {
		# Versioned: the same check get_dbh runs. Dies loudly on any
		# mismatch -- there is no repair branch in any runtime path.
		Munin::Master::Schema::verify($dbh);
	}

	# Initialise the grp _root_ node if not present. Data init, not
	# schema: id 0 is the walk root every group import hangs off.
	unless ($dbh->selectrow_array("SELECT count(1) FROM grp WHERE id = 0")) {
		$dbh->do("INSERT INTO grp (id) VALUES (0);");
	}
	$dbh->commit();
}

sub _db_params_update {
	my ($self, $dbh, $params) = @_;

	my $sth = $dbh->prepare('SELECT name, value FROM param');
	$sth->execute();

	my %old_params;
	while (my ($_name, $_value) = $sth->fetchrow_array()) {
		$old_params{$_name} = $_value;
	}

	$dbh->do('DELETE FROM param');

	my $sth_param = $dbh->prepare('INSERT INTO param (name, value) VALUES (?, ?)');

	# Configuration
	for my $key (sort keys %$params) {
		next if ref $params->{$key};
		$sth_param->execute($key, $params->{$key});
	}

	$dbh->commit();
	return \%old_params;
}

# Import groups and hosts from config tree into SQL.
# Stores group hierarchy in grp, hosts in node, and connection info in node_attr.
sub _db_groups_update {
	my ($self) = @_;

	my $dbh = get_dbh();

	# The config tree is the source of truth for grp/node/node_attr.
	# Diff-based import with FKs enforced the whole way: ids of surviving
	# rows are stable (service/ds/state history hangs off them), and rows
	# gone from the config are swept with their full dependent chains.
	my (@want_groups, @want_hosts);
	my $groups = $config->{groups};
	$self->_config_tree_walk($groups, '', [], \@want_groups, \@want_hosts)
		if $groups && ref $groups eq 'HASH';

	# Current DB state: groups by full path (resolved via the p_id
	# chain), nodes by path with a by-name index to detect group moves.
	my (%db_groups, %db_nodes, %db_nodes_by_name);
	{
		my %grp_by_id;
		my $sth = $dbh->prepare('SELECT id, p_id, name FROM grp');
		$sth->execute();
		while (my $r = $sth->fetchrow_hashref) {
			$grp_by_id{$r->{id}} = $r;
		}
		$sth->finish();
		for my $id (keys %grp_by_id) {
			my ($path, $cur, %seen) = ('', $id);
			while (defined $cur && $cur != 0 && !$seen{$cur}++) {
				$path = $grp_by_id{$cur}{name} . ($path ? ";$path" : '');
				$cur = $grp_by_id{$cur}{p_id};
			}
			$db_groups{$path} = {
				id   => $id,
				name => $grp_by_id{$id}{name},
				p_id => $grp_by_id{$id}{p_id},
			};
		}

		my $sth_n = $dbh->prepare('SELECT id, grp_id, name, path FROM node');
		$sth_n->execute();
		while (my $r = $sth_n->fetchrow_hashref) {
			my $key = defined $r->{path} ? $r->{path} : '';
			$db_nodes{$key} = $r;
			push @{$db_nodes_by_name{$r->{name}}}, $r;
		}
		$sth_n->finish();
	}

	# Groups: upsert along the desired paths (the walk emits parents
	# before children), then sweep leftovers deepest-first.
	my %grp_id_by_path = map { $_ => $db_groups{$_}{id} } keys %db_groups;
	$grp_id_by_path{''} = 0;    # root
	for my $g (@want_groups) {
		my $parent_id = $grp_id_by_path{$g->{parent}};
		my $existing = $db_groups{$g->{path}};
		if (defined $existing) {
			if ($existing->{name} ne $g->{name}
			    || ($existing->{p_id} // -1) != $parent_id) {
				$dbh->prepare('UPDATE grp SET name = ?, p_id = ? WHERE id = ?')
					->execute($g->{name}, $parent_id, $existing->{id});
			}
		} else {
			$dbh->prepare('INSERT INTO grp (p_id, name, path) VALUES (?, ?, ?)')
				->execute($parent_id, $g->{name}, $g->{path});
			$db_groups{$g->{path}} = {
				id   => $dbh->last_insert_id(undef, undef, 'grp', 'id'),
				name => $g->{name},
				p_id => $parent_id,
			};
		}
		$grp_id_by_path{$g->{path}} = $db_groups{$g->{path}}{id};
	}

	my %want_group_path = map { $_->{path} => 1 } @want_groups;
	for my $path (sort { length($b) <=> length($a) || $b cmp $a } keys %db_groups) {
		next if $want_group_path{$path};
		my $id = $db_groups{$path}{id};
		next if $id == 0;
		# Only when no node still references it (the host pass already
		# swept config-gone hosts); otherwise leave it for the next cycle
		# rather than break the FK.
		my ($nb) = $dbh->selectrow_array('SELECT count(1) FROM node WHERE grp_id = ?', undef, $id);
		next if $nb;
		$dbh->prepare('DELETE FROM url WHERE grp_id = ?')->execute($id);
		$dbh->prepare('DELETE FROM grp WHERE id = ?')->execute($id);
	}

	# Hosts
	my %want_host_path = map { $_->{path} => 1 } @want_hosts;
	for my $h (@want_hosts) {
		my $grp_id = $grp_id_by_path{$h->{grp}};
		my $node = $db_nodes{$h->{path}};
		my $old_path;
		if (!defined $node) {
			# The host may have moved groups (its path changed): match by
			# name when unambiguous, so ids -- and the service/ds/state
			# history on them -- survive the move.
			my @same_name = @{$db_nodes_by_name{$h->{name}} || []};
			$node = $same_name[0] if @same_name == 1;
			$old_path = defined $node
				? (defined $node->{path} ? $node->{path} : '')
				: undef;
		}
		if (defined $node) {
			if ($node->{grp_id} != $grp_id || $node->{name} ne $h->{name}
			    || (defined $old_path && $old_path ne $h->{path})) {
				$dbh->prepare('UPDATE node SET grp_id = ?, name = ?, path = ? WHERE id = ?')
					->execute($grp_id, $h->{name}, $h->{path}, $node->{id});
			}
			if (defined $old_path) {
				# Rekey: the moved node must not be swept as stale below
				delete $db_nodes{$old_path};
				$db_nodes{$h->{path}} = $node;
				$node->{path} = $h->{path};
			}
		} else {
			$dbh->prepare('INSERT INTO node (grp_id, name, path) VALUES (?, ?, ?)')
				->execute($grp_id, $h->{name}, $h->{path});
			$node = {
				id     => $dbh->last_insert_id(undef, undef, 'node', 'id'),
				grp_id => $grp_id,
				name   => $h->{name},
				path   => $h->{path},
			};
			$db_nodes{$h->{path}} = $node;
			push @{$db_nodes_by_name{$h->{name}}}, $node;
		}

		# node_attr: sync to the desired set (insert/update/delete)
		my %db_attr;
		my $sth_a = $dbh->prepare('SELECT name, value FROM node_attr WHERE id = ?');
		$sth_a->execute($node->{id});
		while (my ($k, $v) = $sth_a->fetchrow_array) {
			$db_attr{$k} = $v;
		}
		$sth_a->finish();
		for my $k (keys %db_attr) {
			next if exists $h->{attrs}{$k};
			$dbh->prepare('DELETE FROM node_attr WHERE id = ? AND name = ?')
				->execute($node->{id}, $k);
		}
		for my $k (sort keys %{$h->{attrs}}) {
			my $val = $h->{attrs}{$k};
			if (!exists $db_attr{$k}) {
				$dbh->prepare('INSERT INTO node_attr (id, name, value) VALUES (?, ?, ?)')
					->execute($node->{id}, $k, $val);
			} elsif ($db_attr{$k} ne $val) {
				$dbh->prepare('UPDATE node_attr SET value = ? WHERE id = ? AND name = ?')
					->execute($val, $node->{id}, $k);
			}
		}
	}

	# Hosts gone from the config: sweep the full dependent chain
	for my $path (keys %db_nodes) {
		next if $want_host_path{$path};
		$self->_db_remove_node_chain($dbh, $db_nodes{$path}{id});
	}

	$dbh->commit();
	INFO "Imported groups and hosts from config into SQL";
}

# Ordered, FK-safe removal of a node and everything hanging off it.
# Children first, mirroring the FK graph: state/override/ds_rrd/ds_attr
# off ds, the rest off service or node.
sub _db_remove_node_chain {
	my ($self, $dbh, $node_id) = @_;

	DEBUG "_db_remove_node_chain($node_id)";
	my $svc_sql = 'SELECT id FROM service WHERE node_id = ?';
	$dbh->do("DELETE FROM state WHERE node_id = ? OR ds_id IN (SELECT id FROM ds WHERE service_id IN ($svc_sql))",
		undef, $node_id, $node_id);
	$dbh->do("DELETE FROM override WHERE ds_id IN (SELECT id FROM ds WHERE service_id IN ($svc_sql))",
		undef, $node_id);
	$dbh->do("DELETE FROM ds_rrd WHERE ds_id IN (SELECT id FROM ds WHERE service_id IN ($svc_sql))",
		undef, $node_id);
	$dbh->do("DELETE FROM ds_attr WHERE id IN (SELECT id FROM ds WHERE service_id IN ($svc_sql))",
		undef, $node_id);
	$dbh->do("DELETE FROM ds WHERE service_id IN ($svc_sql)", undef, $node_id);
	$dbh->do("DELETE FROM notification_tracking WHERE service_id IN ($svc_sql)", undef, $node_id);
	$dbh->do("DELETE FROM service_attr WHERE id IN ($svc_sql)", undef, $node_id);
	$dbh->do("DELETE FROM service_categories WHERE id IN ($svc_sql)", undef, $node_id);
	$dbh->do("DELETE FROM url WHERE node_id = ? OR service_id IN ($svc_sql)",
		undef, $node_id, $node_id);
	$dbh->do("DELETE FROM service WHERE node_id = ?", undef, $node_id);
	$dbh->do("DELETE FROM node_attr WHERE id = ?", undef, $node_id);
	$dbh->do("DELETE FROM node WHERE id = ?", undef, $node_id);
}

# Walk the config tree emitting the desired groups (pre-order, so
# parents precede children) and hosts. Mirrors the historical import's
# traversal: only groups' hosts and nested groups are visited.
sub _config_tree_walk {
	my ($self, $groups, $parent_path, $path_parts, $want_groups, $want_hosts) = @_;

	for my $group_name (sort keys %$groups) {
		my $group = $groups->{$group_name};
		next unless ref $group;  # Skip non-refs (blessed objects are ok)

		my $grp_path = $parent_path eq '' ? $group_name : "$parent_path;$group_name";
		push @$want_groups, { path => $grp_path, name => $group_name, parent => $parent_path };

		my @current_path = (@$path_parts, $group_name);

		# Hosts in this group
		my $hosts = $group->{hosts};
		if ($hosts && ref $hosts) {
			for my $host_name (sort keys %$hosts) {
				my $host = $hosts->{$host_name};
				next unless ref $host;

				my %attrs;
				for my $attr (qw(address port update update_priority use_node_name)) {
					my $val = $host->{$attr};
					next unless defined $val;
					# Convert Infinity to a large number for storage
					$val = 999999 if $val eq 'Infinity';
					$attrs{$attr} = $val;
				}

				push @$want_hosts, {
					name  => $host_name,
					path  => join(';', @current_path, $host_name),
					grp   => $grp_path,
					attrs => \%attrs,
				};
			}
		}

		# Recurse into nested groups
		my $nested_groups = $group->{groups};
		$self->_config_tree_walk($nested_groups, $grp_path, \@current_path, $want_groups, $want_hosts)
			if $nested_groups && ref $nested_groups;
	}
}

# Import contacts and config overrides from config tree into SQL.
# This is the ONLY time we walk the config tree — after this, everything reads from SQL.
sub _db_import_config {
	my ($self) = @_;

	my $dbh = get_dbh();

	# Config overrides are wiped wholesale: they mirror the config tree and
	# are re-imported below.
	$dbh->do('DELETE FROM override');
	$dbh->do('DELETE FROM config_override');

	# Contacts are upserted by name, not wiped: contact ids must be stable
	# across cycles or the send ledger (keyed by contact_id) resets every
	# run and max_messages throttling never accumulates. Contacts that
	# vanish from config are removed, ledger rows included (FK, no cascade).
	my $contacts = $config->{"contact"};
	my @contact_names;
	if ($contacts && ref $contacts eq 'HASH') {
		for my $child (values %$contacts) {
			next unless ref $child eq 'HASH';
			next if $child->{_};
			my $name = $child->{_}->{name} // next;
			push @contact_names, $name;
		}
	}

	my $sth_c = $dbh->prepare('INSERT OR IGNORE INTO contact (name) VALUES (?)');
	$sth_c->execute($_) for @contact_names;

	if (@contact_names) {
		my $in = join ',', ('?') x @contact_names;
		$dbh->do("DELETE FROM notification_tracking WHERE contact_id NOT IN (SELECT id FROM contact WHERE name IN ($in))", undef, @contact_names);
		$dbh->do("DELETE FROM contact_attr WHERE id NOT IN (SELECT id FROM contact WHERE name IN ($in))", undef, @contact_names);
		$dbh->do("DELETE FROM contact WHERE name NOT IN ($in)", undef, @contact_names);
	} else {
		$dbh->do('DELETE FROM notification_tracking');
		$dbh->do('DELETE FROM contact_attr');
		$dbh->do('DELETE FROM contact');
	}

	my $sth_id  = $dbh->prepare('SELECT id FROM contact WHERE name = ?');
	my $sth_ca  = $dbh->prepare('DELETE FROM contact_attr WHERE id = ?');
	my $sth_ca2 = $dbh->prepare('INSERT INTO contact_attr (id, name, value) VALUES (?, ?, ?)');

	# Walk the config tree for contacts and re-import their attributes
	if ($contacts && ref $contacts eq 'HASH') {
		for my $child (values %$contacts) {
			next unless ref $child eq 'HASH';
			next if $child->{_};

			my $name = $child->{_}->{name} // next;
			my ($contact_id) = $dbh->selectrow_array($sth_id, undef, $name);
			next unless $contact_id;

			$sth_ca->execute($contact_id);

			# Import all attributes
			for my $key (keys %$child) {
				next if $key eq '_';
				my $val = $child->{$key};
				next if ref $val;
				$sth_ca2->execute($contact_id, $key, $val);
			}
		}
	}

	# Import ALL config overrides into config_override table
	# This stores raw config values keyed by (host, service, field, name)
	my $sth_co = $dbh->prepare(q{
		INSERT OR REPLACE INTO config_override (host_name, service_name, field_name, name, value)
		VALUES (?, ?, ?, ?, ?)
	});

	# Walk groups -> hosts -> services -> fields for overrides
	my $groups = $config->{groups};
	if ($groups && ref $groups) {
		for my $group (values %$groups) {
			next unless ref $group;
			my $hosts = $group->{hosts} || next;
			next unless ref $hosts;

			for my $host (values %$hosts) {
				next unless ref $host;
				my $host_name = $host->{host_name} // next;

				# Import host-level overrides (e.g., timeout, retries)
				# Host attributes are stored directly in the host hash
				for my $key (keys %$host) {
					next if grep { $key eq $_ } qw(host_name group groups services);
					my $val = $host->{$key};
					next unless defined $val;
					# Skip service.field attributes (contain dots)
					next if $key =~ /\./;
					$sth_co->execute($host_name, '', '', $key, $val);
				}

				# Import service.field overrides from flattened keys
				# Keys like 'cpu.graph_title', 'cpu.user.warning' etc.
				for my $key (keys %$host) {
					next unless $key =~ /^(\w+)\.(.+)$/;
					my ($service_name, $rest) = ($1, $2);
					my $val = $host->{$key};
					next unless defined $val;

					# Check if it's a service-level or field-level override
					if ($rest =~ /^(\w+)\.(.+)$/) {
						# Field-level: service.field.attr (e.g., cpu.user.warning)
						my ($field_name, $attr) = ($1, $2);
						$sth_co->execute($host_name, $service_name, $field_name, $attr, $val);
					} else {
						# Service-level: service.attr (e.g., cpu.graph_title)
						$sth_co->execute($host_name, $service_name, '', $rest, $val);
					}
				}
			}
		}
	}

	$dbh->commit();
	INFO "Imported contacts and config overrides from config into SQL";
}

1;


__END__

=head1 NAME

Munin::Master::Update - Contacts Munin Nodes, gathers data from their
service data sources, and stores this information in RRD files.

=head1 SYNOPSIS

 my $update = Munin::Master::Update->new();
 $update->run();

=head1 METHODS

=over

=item B<new>

 my $update = Munin::Master::Update->new();

Constructor.

=item B<run>

 $update->run();

This is where all the work gets done.

=back
