package Munin::Master::UpdateWorker;
use base qw(Munin::Master::Worker);

# $Id$

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use File::Basename;
use File::Path;
use File::Spec;
use Munin::Master::Config;
use Munin::Master::Logger;
use Munin::Master::Node;
use Munin::Master::Utils;
use RRDs;
use Time::HiRes;


my $config = Munin::Master::Config->instance()->{config};

sub new {
    my ($class, $host) = @_;

    my $self = $class->SUPER::new("$host->{group}{group_name};$host->{host_name}");
    $self->{host} = $host;
    $self->{node} = Munin::Master::Node->new($host->{address},
                                             $host->{port},
                                             $host->{host_name});

    return $self;
}


sub do_work {
    my ($self) = @_;

    my $update_time = Time::HiRes::time;

    my $lock_file = sprintf '%s/munin-%s-%s.lock',
        $config->{rundir},
            $self->{host}{group}{group_name},
                $self->{host}{host_name};

    munin_getlock($lock_file)
        or croak "Could not get lock for '$self->{host}{host_name}'. Skipping node.";

    my %all_service_configs = ();

    $self->{node}->do_in_session(sub {
        $self->{node}->negotiate_capabilities();
	# Note: A multigraph plugin can present multiple services.
	my @plugins =  $self->{node}->list_services();
        # my @services =

        for my $plugin (@plugins) {
            if (%{$config->{limit_services}}) {
                next unless $config->{limit_services}{$plugin};
            }

            my %service_config = $self->uw_fetch_service_config($plugin);
            unless (%service_config) {
                logger("[WARNING] Service $plugin returned no config");
                next;
            }

            $self->_compare_and_act_on_config_changes($plugin,
                                                      \%service_config);

            my %service_data = eval {
                $self->{node}->fetch_service_data($plugin);
            };
            if ($EVAL_ERROR) {
                logger($EVAL_ERROR);
                next;
            }

            $self->_update_rrd_files($plugin, \%service_config, \%service_data);
            $all_service_configs{$plugin} = \%service_config;
        }

        #use Data::Dumper; warn Dumper(\@services);
    });

    munin_removelock($lock_file);

    return {
        time_used => Time::HiRes::time - $update_time,
        service_configs => \%all_service_configs,
    }
}


sub uw_fetch_service_config {
    # not sure why fetch_service_config needs eval and fetch_service_data
    # does not. - janl 2009.10.22
    my ($self, $plugin) = @_;

    my %service_config = eval {
        $self->{node}->fetch_service_config($plugin);
    };
    if ($EVAL_ERROR) {
        # FIX Report failed service so that we can use the old service
        # config.
        logger($EVAL_ERROR);
        return;
    }

    if ($self->{host}{service_config} && $self->{host}{service_config}{$plugin}) {
        %service_config
            = (%service_config, %{$self->{host}{service_config}{$plugin}});
    }

    return %service_config;
}


sub _compare_and_act_on_config_changes {
    my ($self, $service, $service_config) = @_;

    # Kjellm: Why do we need to tune RRD files after upgrade?
    # Shouldn't we create a upgrade script or something instead?
    #
    # janl: Not sure? Code duplication? Ease of use? Lazyness?

    my $just_upgraded = 0;

    my $old_config = Munin::Master::Config->instance()->{oldconfig};

    if (not defined $old_config->{version}
        or ($old_config->{version}
            ne $Munin::Common::Defaults::MUNIN_VERSION)) {
        $just_upgraded = 1;
    }

    for my $data_source (keys %{$service_config->{data_source}}) {
        my $old_data_source = $data_source;
        my $ds_config = $service_config->{data_source}{$data_source};
        $self->_set_rrd_data_source_defaults($ds_config);

        my $group = $self->{host}{group}{group_name};
        my $host = $self->{host}{host_name};

        my $old_host_config =
            $old_config->{groups}{$group}{hosts}{$host};
        my $old_ds_config =
            $old_host_config->get_canned_ds_config($service,
                                                   $data_source);

        if (not %$old_ds_config
            and defined($ds_config->{oldname})
            and $ds_config->{oldname}) {

            $old_data_source = $ds_config->{oldname};
            $old_ds_config =
                $old_host_config->get_canned_ds_config($service,
                                                       $old_data_source);
        }

        if (%$old_ds_config
            and not $self->_ds_config_eq($old_ds_config, $ds_config)) {
            $self->_ensure_filename($service,
                                    $old_data_source, $data_source,
                                    $old_ds_config, $ds_config)
                and $self->_ensure_tuning($service, $data_source,
                                          $ds_config);
        } elsif ($just_upgraded) {
            $self->_ensure_tuning($service, $data_source,
                                  $ds_config);
        }
    }
}


sub _ds_config_eq {
    my ($self, $old_ds_config, $ds_config) = @_;

    if (%$old_ds_config ne %$ds_config) {
        # Config keys differ:
        return '';
    }

    for my $key (%$old_ds_config) {
        if ((not defined($old_ds_config->{$key}))
            and not defined($ds_config->{$key})) {
            # Both keys undefined, look further:
            next;
        }

        if ((not defined($old_ds_config->{$key}))
            or not defined($ds_config->{$key})) {
            # One key undefined, but not both:
            return '';
        }

        if ($old_ds_config->{$key} ne $ds_config->{$key}) {
            # Config content differs:
            return '';
        }
    }

    return 1;
}


sub _ensure_filename {
    my ($self, $service, $old_data_source, $data_source,
        $old_ds_config, $ds_config) = @_;

    my $rrd_file = $self->_get_rrd_file_name($service, $data_source,
                                             $ds_config);
    my $old_rrd_file = $self->_get_rrd_file_name($service, $old_data_source,
                                                 $old_ds_config);

    if ($rrd_file ne $old_rrd_file) {
        if (-f $old_rrd_file and -f $rrd_file) {
            my $host = $self->{host}{host_name};
            logger("[WARNING]: $host $service $data_source config change"
                   . " suggests moving '$old_rrd_file' to '$rrd_file' but"
                   . " both exist; manually merge the data or remove"
                   . " whichever file you care less about.\n");
            return '';
        } elsif (-f $old_rrd_file) {
            logger("[INFO]: Config update, changing name of '$old_rrd_file'"
                   . " to '$rrd_file'");
            unless (rename ($old_rrd_file, $rrd_file)) {
                logger ("[ERROR]: Could not rename '$old_rrd_file' to"
                        . " '$rrd_file': $!\n");
                return '';
            }
        }
    }

    return 1;
}


sub _ensure_tuning {
    my ($self, $service, $data_source, $ds_config) = @_;
    my $success = 1;

    my $rrd_file =
        $self->_get_rrd_file_name($service, $data_source,
                                  $ds_config);

    my %tune_flags = (type => '--data-source-type',
                      max => '--maximum',
                      min => '--minimum');

    for my $rrd_prop (qw(type max min)) {
        logger("[INFO]: Config update, ensuring $rrd_prop of"
               . " '$rrd_file' is '$ds_config->{$rrd_prop}'.\n");
        RRDs::tune($rrd_file, $tune_flags{$rrd_prop},
                   "42:$ds_config->{$rrd_prop}");
        if (my $tune_error = RRDs::error()) {
            logger("[ERROR] Tuning $rrd_prop of '$rrd_file' to"
                   . " '$ds_config->{$rrd_prop}' failed.\n");
            $success = '';
        }
    }

    return $success;
}


sub _update_rrd_files {
    my ($self, $service, $service_config, $service_data) = @_;

    for my $ds_name (keys %{$service_config->{data_source}}) {
        $self->_set_rrd_data_source_defaults($service_config->{data_source}{$ds_name});

        unless ($service_config->{data_source}{$ds_name}{label}) {
            logger("[ERROR] Unable to update $service -> $ds_name: Missing data source configuration attribute: label");
            next;
        }

        my $rrd_file
            = $self->_create_rrd_file_if_needed($service, $ds_name, 
                                                $service_config->{data_source}{$ds_name});

        if (%$service_data and defined($service_data->{$ds_name})) {
            $self->_update_rrd_file($rrd_file, $ds_name, $service_data->{$ds_name});
        }
        else {
            logger("[WARNING] Service $service returned no data");
        }
    }
}


sub _set_rrd_data_source_defaults {
    my ($self, $data_source) = @_;

    # Test for definedness, anything defined should not be overridden
    # by defaults:
    $data_source->{type} //= 'GAUGE';
    $data_source->{min}  //= 'U';
    $data_source->{max}  //= 'U';
}


sub _create_rrd_file_if_needed {
    my ($self, $service, $ds_name, $ds_config) = @_;

    my $rrd_file = $self->_get_rrd_file_name($service, $ds_name, $ds_config);
    unless (-f $rrd_file) {
        $self->_create_rrd_file($rrd_file, $service, $ds_name, $ds_config);
    }

    return $rrd_file;
}


sub _get_rrd_file_name {
    my ($self, $service, $ds_name, $ds_config) = @_;
    
    my $type_id = lc(substr(($ds_config->{type}), 0, 1));
    my $group = $self->{host}{group}{group_name};
    my $file = sprintf("%s-%s-%s-%s.rrd",
                       $self->{host}{host_name},
                       $service,
                       $ds_name,
                       $type_id);

    # Not really a danger (we're not doing this stuff via the shell),
    # so more to avoid confusion with silly filenames.
    ($group, $file) = map { 
        my $p = $_;
        $p =~ tr/\//_/; 
        $p =~ s/^\./_/g;
        $p;
    } ($group, $file);
	
    logger("[DEBUG] Made rrd filename: $group / $file\n") if $config->{debug};

    return File::Spec->catfile($config->{dbdir}, 
                               $group,
                               $file);
}


sub _create_rrd_file {
    my ($self, $rrd_file, $service, $ds_name, $ds_config) = @_;

    logger("creating rrd-file for $service->$ds_name: '$rrd_file'");
    mkpath(dirname($rrd_file), {mode => oct(777)});
    my @args = (
        $rrd_file,
        sprintf('DS:42:%s:600:%s:%s', 
                $ds_config->{type}, $ds_config->{min}, $ds_config->{max}),
    );
            
    my $resolution = $config->{graph_data_size};
    if ($resolution eq 'normal') {
        push (@args,
              "RRA:AVERAGE:0.5:1:576",   # resolution 5 minutes
              "RRA:MIN:0.5:1:576",
              "RRA:MAX:0.5:1:576",
              "RRA:AVERAGE:0.5:6:432",   # 9 days, resolution 30 minutes
              "RRA:MIN:0.5:6:432",
              "RRA:MAX:0.5:6:432",
              "RRA:AVERAGE:0.5:24:540",  # 45 days, resolution 2 hours
              "RRA:MIN:0.5:24:540",
              "RRA:MAX:0.5:24:540",
              "RRA:AVERAGE:0.5:288:450", # 450 days, resolution 1 day
              "RRA:MIN:0.5:288:450",
              "RRA:MAX:0.5:288:450");
    } 
    elsif ($resolution eq 'huge') {
        push (@args, 
              "RRA:AVERAGE:0.5:1:115200",  # resolution 5 minutes, for 400 days
              "RRA:MIN:0.5:1:115200",
              "RRA:MAX:0.5:1:115200"); 
    }
    RRDs::create @args;
    if (my $ERROR = RRDs::error) {
        logger("[ERROR] Unable to create '$rrd_file': $ERROR");
    }
}


sub _update_rrd_file {
    my ($self, $rrd_file, $ds_name, $ds_values) = @_;

    my $value = $ds_values->{value};

    # Some kind of mismatch between fetch and config can cause this.
    return if !defined($value);  

    if ($value =~ /\d[Ee]([+-]?\d+)$/) {
        # Looks like scientific format.  RRDtool does not
        # like it so we convert it.
        my $magnitude = $1;
        if ($magnitude < 0) {
            # Preserve at least 4 significant digits
            $magnitude = abs($magnitude) + 4;
            $value = sprintf("%.*f", $magnitude, $value);
        } else {
            $value = sprintf("%.4f", $value);
        }
    }

    logger("[DEBUG] Updating $rrd_file with $value") if $config->{debug};
    RRDs::update($rrd_file, "$ds_values->{when}:$value");
    if (my $ERROR = RRDs::error) {
        logger ("[ERROR] In RRD: unable to update $rrd_file: $ERROR");
    }
}

1;


__END__

=head1 NAME

Munin::Master::UpdateWorker - FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

=over

=item B<new>

FIX

=item B<do_work>

FIX

=back

