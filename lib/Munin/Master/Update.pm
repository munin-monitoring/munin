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

my $config_old;
my $config = Munin::Master::Config->instance()->{config};
$config->{version} = $Munin::Common::Defaults::MUNIN_VERSION;


sub new {
    my ($class) = @_;

    # This steals the groups from the master instance of the config.
    my $gah = $config->get_groups_and_hosts();

    my $self = bless {
        STATS               => undef,
        old_service_configs => {},
        old_version         => undef,
        service_configs     => {},
        workers             => [],
        failed_workers      => [],
        group_repository    => Munin::Master::GroupRepository->new($gah),
        config_dump_file    => "$config->{dbdir}/datafile",
    }, $class;
}


sub run {
    my ($self) = @_;

    $self->_create_rundir_if_missing();

    $self->_do_with_lock_and_timing(sub {
        INFO "[INFO]: Starting munin-update";

	# Create the DB, using a local block to close the DB cnx
	{
		my $dbh = get_dbh();
		$self->_db_init($dbh, $dbh);
		$config_old = $self->_db_params_update($dbh, $config);
		$dbh->disconnect();
	}

        $self->{workers} = $self->_create_workers();
        my $nb_workers = $self->_run_workers();
	return $nb_workers;
    });
}

sub get_dbh {
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
	my $dbh = DBI->connect("dbi:$db_driver:dbname=$datafilename", $db_user, $db_passwd) or die $DBI::errstr;
	{
		$dbh->{RaiseError} = 1;
		use Carp;
		$dbh->{HandleError} = sub { confess(shift) };
	 }


	# Plainly returns it, but do *not* put it in $self, as it will let Perl
	# do its GC properly and closing it when out of scope.
	return $dbh;
}

sub _create_rundir_if_missing {
    my ($self) = @_;

    unless (-d $config->{rundir}) {
	mkdir $config->{rundir}, oct(700)
            or croak "Failed to create rundir (".$config->{rundir}."): $!";

    }
}


sub _create_workers {
    my ($self) = @_;

    my @hosts = $self->{group_repository}->get_all_hosts();

    # Shuffle @hosts to avoid always having the same ordering
    # XXX - It might be best to preorder them on the TIMETAKEN ASC
    #       in order that statistically fast hosts are done first to increase
    #       the global throughtput
    @hosts = shuffle(@hosts);

    if (defined $config->{limit_hosts} && %{$config->{limit_hosts}}) {
        @hosts = grep { $config->{limit_hosts}{$_->{host_name}} } @hosts
    }

    # Only create the "update yes" hosts
    @hosts = grep { $_->{update} } @hosts;

    return [ map { Munin::Master::UpdateWorker->new($_) } @hosts ];
}


sub _do_with_lock_and_timing {
    my ($self, $block) = @_;

    my $lock = "$config->{rundir}/munin-update.lock";
    munin_runlock($lock);

    my $update_time = Time::HiRes::time;
    if (!open ($self->{STATS}, '>', "$config->{dbdir}/munin-update.stats.tmp")) {
        WARN "[WARNING] Could not open STATS to $config->{dbdir}/munin-update.stats.tmp: $!";
        # Use /dev/null instead - if the admin won't fix he won't care
        open($self->{STATS}, '>', "/dev/null") or 
	    LOGCROAK "[FATAL] Could not open STATS to /dev/null (fallback for not being able to open $config->{dbdir}/munin-update.stats.tmp): $!";
    }

    # Place global munin-update timeout here.
    my $retval = $block->();

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));
    print { $self->{STATS} } "UT|$update_time\n";
    close ($self->{STATS});
    $self->{STATS} = undef;
    rename ("$config->{dbdir}/munin-update.stats.tmp", "$config->{dbdir}/munin-update.stats");
    INFO "[INFO]: Munin-update finished ($update_time sec)";

    munin_removelock($lock);

    return $retval;
}


sub _run_workers {
	my ($self) = @_;

	use Parallel::ForkManager;

	my $max_processes = $config->{max_processes};

	# Do NOT fork if not set
	$max_processes = 0 unless $config->{fork};

	my $pm = Parallel::ForkManager->new($max_processes);

	# Handle child process failures
	my $nb_workers_failed = 0;
	$pm->run_on_finish(
		sub {
			my ($pid, $exit_code, $ident) = @_;
			INFO "[INFO]: run_on_finish(pid:$pid, exit_code:$exit_code, ident:$ident)";
			$nb_workers_failed++ if $exit_code;
		}
	);

	WORKER_LOOP:
	for my $worker (@{$self->{workers}}) {
		my $worker_pid = $pm->start($worker);
		next WORKER_LOOP if $worker_pid;

		my $res;
		eval {
			# Inject the 2 dbh (meta + state)
			$worker->{dbh} = get_dbh();
			# XXX - It is in the same DB for now
			$worker->{dbh_state} = get_dbh();

			# do_work fails hard on a number of conditions
			$res = $worker->do_work();
		};

		$worker->{dbh}->disconnect();
		$worker->{dbh_state}->disconnect();

		my $worker_id = $worker->{ID};
		if (! defined($res) || $EVAL_ERROR) {
			# No res, something went wrong
			# Note that we handle connection failure same as other
			# failures. Since "do_connect()" fails only softly.
			INFO "[INFO]: no connection or EVAL_ERROR:$EVAL_ERROR";
			$pm->finish(1, [ $worker_id ] );
		}

		$self->_handle_worker_result([$worker_id, $res]);
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
	LOGCROAK("[FATAL] Handle_worker_result got handed a failed worker result");
    }

    my ($worker_id, $time_used, $service_configs) 
        = ($res->[0], $res->[1]{time_used}, $res->[1]{service_configs});

    my $update_time = sprintf("%.2f", $time_used);
    INFO "[INFO]: Munin-update finished for node $worker_id ($update_time sec)";
    if (! defined $self->{STATS} ) {
	# This is may only be the case when we get connection refused
	ERROR "[BUG!] Did not collect any stats for $worker_id.  If this message appears in your logs a lot please email munin-users.  Thanks.";
    } else {
	printf { $self->{STATS} } "UD|%s|%.2f\n", $worker_id, $time_used;
    }

    $self->{service_configs}{$worker_id} = $service_configs;
}

sub _db_init {
	my ($self, $dbh, $dbh_state) = @_;

	my $db_serial_type = "INTEGER";
	my $db_driver = $ENV{MUNIN_DBDRIVER} || "$config->{dbdriver}";
	$db_serial_type = "SERIAL" if $db_driver eq "Pg";

	# Create DB
	$dbh->do("CREATE TABLE IF NOT EXISTS param (name VARCHAR PRIMARY KEY, value VARCHAR)");
	$dbh->do("CREATE TABLE IF NOT EXISTS grp (id $db_serial_type PRIMARY KEY, p_id INTEGER REFERENCES grp(id), name VARCHAR, path VARCHAR)");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS r_g_grp ON grp (p_id, name)");
	$dbh->do("CREATE TABLE IF NOT EXISTS node (id $db_serial_type PRIMARY KEY, grp_id INTEGER REFERENCES grp(id), name VARCHAR, path VARCHAR)");
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
	$dbh->do("CREATE TABLE IF NOT EXISTS url (id INTEGER NOT NULL, type VARCHAR NOT NULL, path VARCHAR NOT NULL, PRIMARY KEY(id,type))");
	$dbh->do("CREATE UNIQUE INDEX IF NOT EXISTS u_url_path ON url (path)");

	# Note, this table is referenced by composite key (type,id) in order to be
	# able to have any kind of states. Such as whole node states for example.
	$dbh_state->do("CREATE TABLE IF NOT EXISTS state (id INTEGER, type VARCHAR,
		last_epoch INTEGER, last_value VARCHAR,
		prev_epoch INTEGER, prev_value VARCHAR,
		alarm VARCHAR, num_unknowns INTEGER
		)");
	$dbh_state->do("CREATE UNIQUE INDEX IF NOT EXISTS pk_state ON state (type, id)");

	# Initialise the grp _root_ node if not present
	unless ($dbh->selectrow_array("SELECT count(1) FROM grp WHERE id = 0")) {
		$dbh->do("INSERT INTO grp (id) VALUES (0);");
	}
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

	return \%old_params;
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

