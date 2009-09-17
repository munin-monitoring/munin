package Munin::Master::Update;

# $Id$

use warnings;
use strict;

use Carp;
use Munin::Common::Defaults;
use Munin::Master::Config;
use Munin::Master::GroupRepository;
use Munin::Master::Logger;
use Munin::Master::UpdateWorker;
use Munin::Master::ProcessManager;
use Munin::Master::Utils;
use Time::HiRes;

my $config = Munin::Master::Config->instance();

sub new {
    my ($class) = @_;

    my %gah = $config->get_groups_and_hosts();

    return bless {
        STATS               => undef,
        old_service_configs => {},
        old_version         => undef,
        service_configs     => {},
        workers             => [],
        failed_workers      => [],
        group_repository    => Munin::Master::GroupRepository->new(\%gah),
        config_dump_file    => "$config->{dbdir}/datafile",
    }, $class;
}


sub run {
    my ($self) = @_;
    
    $self->_create_rundir_if_missing();

    $self->_do_with_lock_and_timing(sub {
        logger("Starting munin-update");

        $self->{workers} = $self->_create_workers();
        $self->_run_workers();
        $self->{old_service_configs} = $self->_read_old_service_configs();
        $self->_compare_and_act_on_config_changes();
        $self->_write_new_service_configs_locked();
    });
}


sub _create_rundir_if_missing {
    my ($self) = @_;

    unless (-d $config->{rundir}) {
	mkdir $config->{rundir}, oct(700)
            or croak "Failed to create rundir: $!";
        
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
        logger("[WARNING] Unable to open $config->{dbdir}/munin-update.stats");
        # Use /dev/null instead - if the admin won't fix he won't care
        open($self->{STATS}, '>', "/dev/null") or die "Could not open STATS to /dev/null: $?";
    }

    my $retval = $block->();

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));
    print { $self->{STATS} } "UT|$update_time\n";
    close ($self->{STATS});
    $self->{STATS} = undef;
    rename ("$config->{dbdir}/munin-update.stats.tmp", "$config->{dbdir}/munin-update.stats");
    logger("Munin-update finished ($update_time sec)");

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
            my $res = $worker->do_work();
            $self->_handle_worker_result([$worker->{ID}, $res]);
        }
    }
}


sub _create_self_aware_worker_result_handler {
    my ($self) = @_;

    return sub { $self->_handle_worker_result(@_); };
}


sub _handle_worker_result {
    my ($self, $res) = @_;

    my ($worker_id, $time_used, $service_configs) 
        = ($res->[0], $res->[1]{time_used}, $res->[1]{service_configs});

    printf { $self->{STATS} } "UD|%s|%.2f\n", $worker_id, $time_used;

    $self->{service_configs}{$worker_id} = $service_configs;
}


sub _create_self_aware_worker_exception_handler {
    my ($self) = @_;

    return sub {
        my ($worker_id, $reason) = @_;
	# FIXME: $worker_id is not defined!
	logger("Failed worker $worker_id");
        push @{$self->{failed_workers}}, $worker_id;
    };
}


sub _read_old_service_configs {
    my ($self) = @_;

    return {} unless -e $self->{config_dump_file};

    open my $dump, '<', $self->{config_dump_file}
        or croak "Fatal error: Could not open '$self->{config_dump_file}' for reading: $!";

    my %service_configs = $self->_parse_service_config_dump($dump);

    close $dump
        or croak "Fatal error: Could not close '$self->{config_dump_file}': $!";

    #use Data::Dumper; warn Dumper(\%service_configs);

    return \%service_configs;
    
}


sub _parse_service_config_dump {
    my ($self, $io) = @_;

    my %service_configs = ();

    my $version = <$io>;
    chop $version;
    $self->{old_version} =  substr $version, length('version ');

    while (my $line = <$io>) {
        chop $line;

	# Format is group;...:host.service.field.attribute 
        my ($key, $value) = split(/ /, $line);

	my ($grouphost,$ss) = split(/:/, $key);

	my ($service,@rest) = split(/\./, $ss);

	my @key_components = split(/;/, $grouphost);

	my $host = pop(@key_components);

        if (@key_components == 1 || @key_components == 3) {
            # Ignore. These are configuration variables from
            # $CONF_DIR/munin.conf. We only care about service
            # configuration.
            next;
        }
        
        my $group = join(';', @key_components);

        $host = "$group;$host";

        #use Data::Dumper; warn Dumper([$host, $value, \@attribute]);

        $service_configs{$host} ||= {};

	if (defined($service)) {
	    $service_configs{$host}{$service} ||= 
	    {global => [], data_source => {}};

	    if (@rest == 2) {
		$service_configs{$host}{$service}{data_source}{$rest[0]} ||= {};
		$service_configs{$host}{$service}{data_source}{$rest[0]}{$rest[1]} = $value;
	    } else {
		push @{$service_configs{$host}{$service}{global}}, [@rest, $value];
	    }
        } # Don't we need a else here?
    }

    return %service_configs;
}


sub _compare_and_act_on_config_changes {
    my ($self) = @_;

    # FIX why do we need to tune RRD files after upgrade? Shouldn't we
    # create a upgrade script or something instead?
    my $just_upgraded = 0;

    if (!defined $self->{old_version} 
            || $self->{old_version} ne $Munin::Common::Defaults::MUNIN_VERSION) {
        $just_upgraded = 1;
    }

    my %changers = (
        'max'  => \&_change_max,
        'min'  => \&_change_min,
        'type' => \&_change_type,
    );

    for my $host (keys %{$self->{service_configs}}) {
        for my $service (keys %{$self->{service_configs}{$host}}) {
            for my $data_source (keys %{$self->{service_configs}{$host}{$service}{data_source}}) {
                my $ds_config = $self->{service_configs}{$host}{$service}{data_source}{$data_source};
                my $old_ds_config = $self->{old_service_configs}{$host} 
                    && $self->{old_service_configs}{$host}{$service}
                        && $self->{old_service_configs}{$host}{$service}{data_source}{$data_source};

                next unless $old_ds_config || $just_upgraded;

                $old_ds_config ||= {max => '', min => '', type => 'GAUGE'};
                
                my $rrd_file 
                    = $self->_get_rrd_file_name($host, $service, $data_source, $ds_config->{type});

                # type must come last because it renames the file
                # referenced by min and max ($rrd_file)
                for my $what (qw(min max type)) {
                    if ($just_upgraded || $ds_config->{$what} ne $old_ds_config->{$what}) {
                        logger("Notice: compare_configs: $host.$service.$data_source.$what changed from '" 
                                   . (defined $old_ds_config->{$what} ? $old_ds_config->{$what} : "undefined") 
                                       . "' to '$ds_config->{$what}'.");
                        $changers{$what}->($self, $ds_config->{$what}, $rrd_file);
                    }
                }
            }
        }
    }
}


sub _change_type {
    my ($self, $new, $file) = @_;

    $new ||= 'GAUGE';

    my $type_id = lc(substr($new, 0, 1));
    my $new_file = $file;
    $new_file =~ s/\w.rrd/$type_id.rrd/;

    logger("[INFO]: Changing name of $file to $new_file");
    unless (rename ($file, $new_file)) {
        logger ("[ERROR]: Could not rename '$file': $!\n");
    }
    

    logger("[INFO]: Changing type of $new_file to \"$new\",\n");
    RRDs::tune($new_file, "-d", "42:$new");
}


sub _change_max {
    my ($self, $new, $file) = @_;

    $new ||= 'U';

    logger("[INFO]: Changing max of \"$file\" to \"$new\".\n");
    RRDs::tune($file, "-a", "42:$new");
}


sub _change_min {
    my ($self, $new, $file) = @_;

    $new ||= 'U';

    logger("[INFO]: Changing min of \"$file\" to \"$new\".\n");
    RRDs::tune($file, "-i", "42:$new");
}


# FIX merge with Update::Worker::_get_rrd_file_name
sub _get_rrd_file_name {
    my ($self, $host, $service, $ds_name, $ds_type) = @_;
    
    my $type_id = lc(substr(($ds_type), 0, 1));
    my ($g, $h) = split /;/, $host;
    my $file = sprintf("%s-%s-%s-%s.rrd",
                       $h,
                       $service,
                       $ds_name,
                       $type_id);

    # Not really a danger (we're not doing this stuff via the shell),
    # so more to avoid confusion with silly filenames.
    ($g, $file) = map { 
        my $p = $_;
        $p =~ tr/\//_/; 
        $p =~ s/^\./_/g;
        $p;
    } ($g, $file);
	
    my $rrd_file = File::Spec->catfile($config->{dbdir}, 
                                       $g,
                                       $file);
    croak "RRD file '$rrd_file' not found" unless -e $rrd_file;

    return $rrd_file;
}


sub _write_new_service_configs_locked {
    my ($self) = @_;

    my $lock_file = "$config->{rundir}/munin-datafile.lock";
    munin_runlock($lock_file);

    open my $dump, '>', $self->{config_dump_file}
        or croak "Fatal error: Could not open '$self->{config_dump_file}' for writing: $!";

    $self->_write_new_service_configs($dump);

    close $dump
        or croak "Fatal error: Could not close '$self->{config_dump_file}': $!";

    munin_removelock($lock_file);
}


sub _write_new_service_configs {
    my ($self, $io) = @_;

    $self->_copy_old_service_config_for_failed_workers();

    print $io "version $Munin::Common::Defaults::MUNIN_VERSION\n";
    for my $host (keys %{$self->{service_configs}}) {
        for my $service (keys %{$self->{service_configs}{$host}}) {
            for my $attr (@{$self->{service_configs}{$host}{$service}{global}}) {
                print $io "$host:$service.$attr->[0] $attr->[1]\n";
            }
            for my $data_source (keys %{$self->{service_configs}{$host}{$service}{data_source}}) {
                for my $attr (keys %{$self->{service_configs}{$host}{$service}{data_source}{$data_source}}) {
                    print $io "$host:$service.$data_source.$attr $self->{service_configs}{$host}{$service}{data_source}{$data_source}{$attr}\n";
                }
            }
        }
    }
}


sub _copy_old_service_config_for_failed_workers {
    my ($self) = @_;

    for my $worker (@{$self->{failed_workers}}) {
	next if !defined($worker);  # The empty set contains "undef" it seems
        $self->{service_configs}{$worker} = $self->{old_service_configs}{$worker};
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

