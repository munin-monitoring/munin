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

	$self->{runid} = time() unless $self->{runid};
	my $runid = $self->{runid};
	my $dbh = $self->{dbh} || get_dbh(); # Reuse any existing connection, or open a temporary one
	my $dbh_driver = $dbh->{Driver}->{Name};
	my $sql_to_timestamp = "";
	$sql_to_timestamp = "TO_TIMESTAMP" if $dbh_driver eq "Pg";
	my $sth_i = $dbh->prepare_cached("INSERT INTO stats (runid, tstp, type, name, duration) VALUES (?, $sql_to_timestamp(?), ?, ?, ?);");
	$sth_i->execute($runid, time(), $type, $name, $duration);
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

	my $db_serial_type = "INTEGER";
	my $db_driver = $ENV{MUNIN_DBDRIVER} || "$config->{dbdriver}";
	$db_serial_type = "SERIAL" if $db_driver eq "Pg";

	# Sets some session vars
	$dbh->do("SET LOCAL client_min_messages = error") if $db_driver eq "Pg";

	# Initialize DB Schema
	$dbh->do("CREATE TABLE IF NOT EXISTS param (name VARCHAR PRIMARY KEY, value VARCHAR)");
	$dbh->do("CREATE TABLE IF NOT EXISTS grp (id $db_serial_type PRIMARY KEY, p_id INTEGER REFERENCES grp(id), name VARCHAR, path VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS r_g_grp ON grp (p_id, name)");
	$dbh->do("CREATE TABLE IF NOT EXISTS node (id $db_serial_type PRIMARY KEY, grp_id INTEGER REFERENCES grp(id), name VARCHAR, path VARCHAR, spoolepoch INTEGER)");
	$dbh->do("CREATE TABLE IF NOT EXISTS node_attr (id INTEGER REFERENCES node(id), name VARCHAR, value VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_node_attr ON node_attr (id, name)");
	$dbh->do("CREATE INDEX IF NOT EXISTS r_n_grp ON node (grp_id)");
	$dbh->do("CREATE TABLE IF NOT EXISTS service (id $db_serial_type PRIMARY KEY, node_id INTEGER REFERENCES node(id), name VARCHAR, path VARCHAR, service_title VARCHAR, graph_info VARCHAR, subgraphs INTEGER)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS u_service_n_n ON service (node_id, name)");
	$dbh->do("CREATE TABLE IF NOT EXISTS service_attr (id INTEGER REFERENCES service(id), name VARCHAR, value VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_service_attr ON service_attr (id, name)");
	$dbh->do("CREATE TABLE IF NOT EXISTS service_categories (id INTEGER REFERENCES service(id), category VARCHAR NOT NULL, PRIMARY KEY (id,category))");
	$dbh->do("CREATE INDEX IF NOT EXISTS r_s_node ON service (node_id)");
	$dbh->do("CREATE TABLE IF NOT EXISTS ds (id $db_serial_type PRIMARY KEY, service_id INTEGER REFERENCES service(id), name VARCHAR, path VARCHAR,
		type VARCHAR DEFAULT 'GAUGE',
		ordr INTEGER DEFAULT 0,
		unknown INTEGER DEFAULT 0, warning INTEGER DEFAULT 0, critical INTEGER DEFAULT 0)");
	$dbh->do("CREATE TABLE IF NOT EXISTS ds_attr (id INTEGER REFERENCES ds(id), name VARCHAR, value VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_ds_attr ON ds_attr (id, name)");
	$dbh->do("CREATE INDEX IF NOT EXISTS r_d_service ON ds (service_id)");

	# Table that contains all the URL paths, in order to have a very fast lookup
	# FK to grp/node/service - no cascade, error if referenced
	# path is the identity (lookups are by path), no surrogate id needed
	$dbh->do("CREATE TABLE IF NOT EXISTS url (
		path VARCHAR PRIMARY KEY,
		grp_id INTEGER REFERENCES grp(id),
		node_id INTEGER REFERENCES node(id),
		service_id INTEGER REFERENCES service(id),
		CHECK ((grp_id IS NOT NULL) + (node_id IS NOT NULL) + (service_id IS NOT NULL) = 1)
	)");

	# Per-entity state tracking. FK columns instead of polymorphic (type,id) --
	# no cascade, error if referenced. CHECK ensures exactly one FK is set.
	# prev_alarm/eval_value/extinfo are written by the limits evaluation and
	# read by the serial notification tail: prev_alarm gives edge detection
	# (alarm != prev_alarm == state just changed), eval_value/extinfo are the
	# message content so notifications can be rebuilt from the DB alone.
	$dbh->do("CREATE TABLE IF NOT EXISTS state (
		ds_id INTEGER REFERENCES ds(id),
		node_id INTEGER REFERENCES node(id),
		last_epoch INTEGER, last_value VARCHAR,
		prev_epoch INTEGER, prev_value VARCHAR,
		alarm VARCHAR, num_unknowns INTEGER DEFAULT 0,
		prev_alarm VARCHAR, eval_value VARCHAR, extinfo VARCHAR,
		CHECK ((ds_id IS NOT NULL) + (node_id IS NOT NULL) = 1)
	)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_state_ds ON state (ds_id)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_state_node ON state (node_id)");

	# Migrate pre-existing state tables (CREATE IF NOT EXISTS skips them)
	if ($db_driver eq "Pg") {
		for my $col (qw(prev_alarm eval_value extinfo)) {
			$dbh->do("ALTER TABLE state ADD COLUMN IF EXISTS $col VARCHAR");
		}
	} else {
		my %state_cols = map { $_->[1] => 1 }
			@{ $dbh->selectall_arrayref("PRAGMA table_info(state)") };
		for my $col (qw(prev_alarm eval_value extinfo)) {
			next if $state_cols{$col};
			$dbh->do("ALTER TABLE state ADD COLUMN $col VARCHAR");
		}
	}

	# Munin stats
	$dbh->do("CREATE TABLE IF NOT EXISTS stats (runid VARCHAR NOT NULL, tstp TIMESTAMPTZ, type VARCHAR, name VARCHAR, duration NUMERIC)");

	# Contacts for notification
	$dbh->do("CREATE TABLE IF NOT EXISTS contact (id $db_serial_type PRIMARY KEY, name VARCHAR UNIQUE)");
	$dbh->do("CREATE TABLE IF NOT EXISTS contact_attr (id INTEGER REFERENCES contact(id), name VARCHAR, value VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_contact_attr ON contact_attr (id, name)");

	# Send ledger: last-sent severity, sent_at, throttle counter num_messages.
	# NOT config -- decision inputs are state.alarm (current), contact attrs
	# (always_send/command/text), and this ledger (dupe avoidance). Renamed
	# from `notification` accordingly; migration below renames in place.
	$dbh->do("CREATE TABLE IF NOT EXISTS notification_tracking (
		id $db_serial_type PRIMARY KEY,
		contact_id INTEGER REFERENCES contact(id),
		service_id INTEGER REFERENCES service(id),
		severity VARCHAR,
		sent_at INTEGER,
		num_messages INTEGER DEFAULT 0
	)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS u_notification_tracking ON notification_tracking (contact_id, service_id)");

	# Migrate the pre-rename table. The ledger must survive: it carries
	# transition memory (throttling) across cycles.
	my ($old_notif) = $db_driver eq "Pg"
		? $dbh->selectrow_array("SELECT to_regclass('notification')")
		: $dbh->selectrow_array("SELECT name FROM sqlite_master WHERE type='table' AND name='notification'");
	if ($old_notif) {
		$dbh->do("ALTER TABLE notification RENAME TO notification_tracking");
		$dbh->do("DROP INDEX IF EXISTS u_notification");
		$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS u_notification_tracking ON notification_tracking (contact_id, service_id)");
	}

	# Config file overrides — plugin defaults go to ds_attr, config overrides go here
	$dbh->do("CREATE TABLE IF NOT EXISTS override (ds_id INTEGER REFERENCES ds(id), name VARCHAR, value VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_override ON override (ds_id, name)");

	# Config import overrides — raw config values keyed by host/service/field
	# Stores everything from munin.conf before inheritance resolution
	$dbh->do("CREATE TABLE IF NOT EXISTS config_override (
		host_name VARCHAR NOT NULL,
		service_name VARCHAR NOT NULL DEFAULT '',
		field_name VARCHAR NOT NULL DEFAULT '',
		name VARCHAR NOT NULL,
		value VARCHAR,
		PRIMARY KEY (host_name, service_name, field_name, name)
	)");

	# Initialise the grp _root_ node if not present
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

	# Clear existing groups, nodes, node attributes, and URLs
	# URLs must be cleared too - they have UNIQUE constraint on path
	#
	# NOTE: this legacy wipe-and-reimport relies on id-churn stability: the
	# service/ds/state tables reference node/grp ids that get re-created with
	# identical ids each cycle (full wipe + same import order). FK enforcement
	# would reject the wipe (services still reference the old node rows), so
	# this one connection runs with FK off. Proper fix is a diff-based upsert
	# import (see mission log follow-ups).
	my $db_driver = $ENV{MUNIN_DBDRIVER} || "$config->{dbdriver}";
	$dbh->{AutoCommit} = 1;  # commit+detach, so the PRAGMA runs outside a txn
	$dbh->do("PRAGMA foreign_keys=OFF;") if $db_driver eq "SQLite";
	$dbh->{AutoCommit} = 0;
	$dbh->do('DELETE FROM node_attr');
	$dbh->do('DELETE FROM node');
	$dbh->do('DELETE FROM url');
	$dbh->do('DELETE FROM grp WHERE id != 0');  # Keep root

	my $sth_grp = $dbh->prepare('INSERT INTO grp (p_id, name) VALUES (?, ?)');
	my $sth_node = $dbh->prepare('INSERT INTO node (grp_id, name, path) VALUES (?, ?, ?)');
	my $sth_attr = $dbh->prepare('INSERT INTO node_attr (id, name, value) VALUES (?, ?, ?)');

	# Walk the config tree for groups and hosts
	my $groups = $config->{groups};
	if ($groups && ref $groups eq 'HASH') {
		$self->_import_groups_recursive($dbh, $groups, 0, []);
	}

	$dbh->commit();
	INFO "Imported groups and hosts from config into SQL";
}

# Recursively import groups and their hosts into the DB.
sub _import_groups_recursive {
	my ($self, $dbh, $groups, $p_id, $path_parts) = @_;

	my $sth_grp = $dbh->prepare('INSERT INTO grp (p_id, name) VALUES (?, ?)');
	my $sth_node = $dbh->prepare('INSERT INTO node (grp_id, name, path) VALUES (?, ?, ?)');
	my $sth_attr = $dbh->prepare('INSERT INTO node_attr (id, name, value) VALUES (?, ?, ?)');

	for my $group_name (sort keys %$groups) {
		my $group = $groups->{$group_name};
		next unless ref $group;  # Skip non-refs (blessed objects are ok)

		# Insert group
		$sth_grp->execute($p_id, $group_name);
		my $grp_id = $dbh->last_insert_id(undef, undef, 'grp', 'id');

		# Track path for this group
		my @current_path = (@$path_parts, $group_name);

		# Import hosts in this group
		my $hosts = $group->{hosts};
		if ($hosts && ref $hosts) {
			for my $host_name (sort keys %$hosts) {
				my $host = $hosts->{$host_name};
				next unless ref $host;

				# Build full path: group1;group2;host
				my $full_path = join(';', @current_path, $host_name);

				# Insert node
				$sth_node->execute($grp_id, $host_name, $full_path);
				my $node_id = $dbh->last_insert_id(undef, undef, 'node', 'id');

				# Insert node attributes
				for my $attr (qw(address port update update_priority use_node_name)) {
					my $val = $host->{$attr};
					next unless defined $val;
					# Convert Infinity to a large number for storage
					$val = 999999 if $val eq 'Infinity';
					$sth_attr->execute($node_id, $attr, $val);
				}
			}
		}

		# Recurse into nested groups
		my $nested_groups = $group->{groups};
		if ($nested_groups && ref $nested_groups) {
			$self->_import_groups_recursive($dbh, $nested_groups, $grp_id, \@current_path);
		}
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
