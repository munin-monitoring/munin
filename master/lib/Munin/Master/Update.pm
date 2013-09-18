package Munin::Master::Update;

# $Id$

use warnings;
use strict;

use English qw(-no_match_vars);
use Carp;

use Time::HiRes;
use Log::Log4perl qw( :easy );

use Munin::Common::Defaults;
use Munin::Master::Config;
use Munin::Master::Logger;
use Munin::Master::UpdateWorker;
use Munin::Master::ProcessManager;
use Munin::Master::Utils;

my $config = Munin::Master::Config->instance()->{config};

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

        $self->{old_service_configs} = $self->_read_old_service_configs();

        $self->{workers} = $self->_create_workers();
        $self->_run_workers();

	# I wonder if the following should really be done with timing. - janl
        $self->_write_new_service_configs();
    });
}


sub _read_old_service_configs {

    # Read the datafile containing old configurations.  This should
    # not fail in case of problems with the file.  In such a case the
    # file should simply be ingored and a new one written.  Lets hope
    # it does not repeat itself then.

    my ($self) = @_;

    # Get old service configuration from the config instance since the
    # syntaxes are identical.
    my $oldconfig = Munin::Master::Config->instance()->{oldconfig};

    my $datafile = $oldconfig->{config_file} = $config->{dbdir}.'/datafile';

    $oldconfig = munin_read_storable("$datafile.storable", $oldconfig);

    return $oldconfig;
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

    # FIX log skipped and queued workers:
    # logger("Skipping '$name' (update disabled by config)");
    # logger("Queuing '$name' for update.");

    my @hosts = $self->{group_repository}->get_all_hosts();

    if (%{$config->{limit_hosts}}) {
        @hosts = grep { $config->{limit_hosts}{$_->{host_name}} } @hosts
    }

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

    if ($config->{fork}) {
        my $pm = Munin::Master::ProcessManager
            ->new($self->_create_self_aware_worker_result_handler(),
                  $self->_create_self_aware_worker_exception_handler());
        $pm->add_workers(@{$self->{workers}});
        $pm->start_work();
    }
    else {
        for my $worker (@{$self->{workers}}) {

	    my $res ;

	    eval {
		# do_work fails hard on a number of conditions
		$res = $worker->do_work();
	    };

	    $res=undef if $EVAL_ERROR;

	    my $worker_id = $worker->{ID};
	    if (defined($res)) {
		$self->_handle_worker_result([$worker_id, $res]);
	    } else {
		# Need to handle connection failure same as other
		# failures.  do_connect fails softly.
		WARN "[WARNING] Failed worker ".$worker_id."\n";
		push @{$self->{failed_workers}}, $worker_id;
	    }
        }
    }
}


sub _create_self_aware_worker_result_handler {
    my ($self) = @_;

    return sub { $self->_handle_worker_result(@_); };
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


sub _create_self_aware_worker_exception_handler {
    my ($self) = @_;

    return sub {
        my ($worker, $reason) = @_;
	my $worker_id = $worker->{ID};
	DEBUG "[DEBUG] In exception handler for failed worker $worker_id";
        push @{$self->{failed_workers}}, $worker_id;
    };
}

sub _get_last_insert_id {
	my ($dbh) = @_;
	return $dbh->last_insert_id("", "", "", "");
}

sub _dump_into_sql {
	my ($self) = @_;

	my $datafilename = $config->{dbdir}."/datafile.sqlite";
	my $datafilename_tmp = "$datafilename.tmp.$$";
	DEBUG "[DEBUG] Writing sql to $datafilename";

        use DBI;
        my $dbh = DBI->connect("dbi:SQLite:dbname=$datafilename_tmp","","") or die $DBI::errstr;
        $dbh->do("PRAGMA synchronous = 0");

        # <helmut> halves io bandwidth at the expense of dysfunctional rollback
        # We do not care for rollback yet
        $dbh->do("PRAGMA journal_mode = OFF");

        # Create DB
        $dbh->do("CREATE TABLE param (name VARCHAR PRIMARY KEY, value VARCHAR)");
	my $sth_param = $dbh->prepare('INSERT INTO param (name, value) VALUES (?, ?)');

        $dbh->do("CREATE TABLE node (id INTEGER PRIMARY KEY, name VARCHAR, path VARCHAR)");
        $dbh->do("CREATE TABLE node_attr (id INTEGER REFERENCES node(id), name VARCHAR, value VARCHAR)");
        $dbh->do("CREATE UNIQUE INDEX pk_node_attr ON node_attr (id, name)");
	my $sth_node = $dbh->prepare('INSERT INTO node (name, path) VALUES (?, ?)');
	my $sth_node_attr = $dbh->prepare('INSERT INTO node_attr (id, name, value) VALUES (?, ?, ?)');

        $dbh->do("CREATE TABLE service (id INTEGER PRIMARY KEY, node_id INTEGER REFERENCES node(id), name VARCHAR, path VARCHAR)");
        $dbh->do("CREATE TABLE service_attr (id INTEGER REFERENCES service(id), name VARCHAR, value VARCHAR)");
        $dbh->do("CREATE UNIQUE INDEX pk_service_attr ON service_attr (id, name)");
	my $sth_service = $dbh->prepare('INSERT INTO service (node_id, name, path) VALUES (?, ?, ?)');
	my $sth_service_attr = $dbh->prepare('INSERT INTO service_attr (id, name, value) VALUES (?, ?, ?)');
	
        $dbh->do("CREATE TABLE ds (id INTEGER PRIMARY KEY, service_id INTEGER REFERENCES service(id), name VARCHAR, path VARCHAR)");
        $dbh->do("CREATE TABLE ds_attr (id INTEGER REFERENCES ds(id), name VARCHAR, value VARCHAR)");
        $dbh->do("CREATE UNIQUE INDEX pk_ds_attr ON ds_attr (id, name)");
	my $sth_ds = $dbh->prepare('INSERT INTO ds (service_id, name, path) VALUES (?, ?, ?)');
	my $sth_ds_attr = $dbh->prepare('INSERT INTO ds_attr (id, name, value) VALUES (?, ?, ?)');

	# Configuration
	$config->{version} = $Munin::Common::Defaults::MUNIN_VERSION;
	for my $key (keys %$config) {
		next if ref $config->{$key};
		$sth_param->execute($key, $config->{$key});
	}

	for my $host (keys %{$self->{service_configs}}) {
		$sth_node->execute($host, $host);
		my $host_id = _get_last_insert_id($dbh);

		for my $service (keys %{$self->{service_configs}{$host}{data_source}}) {
			$sth_service->execute($host_id, $service, "$host:$service");
			my $service_id = _get_last_insert_id($dbh);

			for my $attr (@{$self->{service_configs}{$host}{global}{$service}}) {
				$sth_service_attr->execute($service_id, $attr->[0], $attr->[1]);
			}
			for my $data_source (keys %{$self->{service_configs}{$host}{data_source}{$service}}) {
				$sth_ds->execute($service_id, $data_source, "$host:$service.$data_source");
				my $ds_id = _get_last_insert_id($dbh);
				for my $attr (keys %{$self->{service_configs}{$host}{data_source}{$service}{$data_source}}) {
					$sth_ds_attr->execute($ds_id, $attr, $self->{service_configs}{$host}{data_source}{$service}{$data_source}{$attr});
				}
			}
		}
	}

	# Atomic commit (rename)
	rename($datafilename_tmp, $datafilename);
}

sub _write_new_service_configs {
    my ($self) = @_;
    my $datafile_hash = {};

    $datafile_hash->{version} = $Munin::Common::Defaults::MUNIN_VERSION;

    $self->_print_service_configs_for_not_updated_services($datafile_hash);
    $self->_print_old_service_configs_for_failed_workers($datafile_hash);

    my $fh = new IO::File(">self.txt");
    print $fh munin_dumpconfig_as_str($self);

    $self->_dump_into_sql();

    for my $host (keys %{$self->{service_configs}}) {
        for my $service (keys %{$self->{service_configs}{$host}{data_source}}) {
            for my $attr (@{$self->{service_configs}{$host}{global}{$service}}) {
                munin_set_var_path($datafile_hash, "$host:$service.$attr->[0]", $attr->[1]);
            }
            for my $data_source (keys %{$self->{service_configs}{$host}{data_source}{$service}}) {
                for my $attr (keys %{$self->{service_configs}{$host}{data_source}{$service}{$data_source}}) {
                    munin_set_var_path($datafile_hash, "$host:$service.$data_source.$attr", $self->{service_configs}{$host}{data_source}{$service}{$data_source}{$attr});
                }
            }
        }
    }

    # Also write the binary (Storable) version
    munin_writeconfig_storable($config->{dbdir}.'/datafile.storable', $datafile_hash);
}


sub _print_service_configs_for_not_updated_services {
    my ($self, $datafile_hash) = @_;

    my @hosts = $self->{group_repository}->get_all_hosts();

    for my $workerdata (@hosts) {
        my $worker = $workerdata->get_full_path();

        my @data = grep { /\.update$/ and !$workerdata->{$_} } keys %$workerdata;
        for my $match (@data) {
            my $prefix = substr $match, 0, -6;

            for my $datum (grep { /^\Q$prefix\E/ } keys %$workerdata) {
                munin_set_var_path($datafile_hash, $worker . ":". $datum, $workerdata->{$datum});
            }

        }

    }
}


sub _print_old_service_configs_for_failed_workers {
    my ($self, $datafile_hash) = @_;

    for my $worker (@{$self->{failed_workers}}) {
	# The empty set contains "undef" it seems
	next if !defined($worker);  

	my $workerdata = $self->{old_service_configs}->look_up($worker);

	# No data available on the failed worker
	if (!defined($workerdata)) {
	    INFO "[INFO] No old data available for failed worker $worker.  This node will disappear from the html web page hierarchy\n";
	    next;
	}
	
	for my $datum (keys %$workerdata) {
	    # Skip some book-keeping
	    next if ($datum eq 'group')
		or ($datum eq 'host_name');

	    munin_set_var_path($datafile_hash, $worker . ":". $datum, $workerdata->{$datum});
	}
	
    }
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

