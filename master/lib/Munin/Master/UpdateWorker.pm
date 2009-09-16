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


my $config = Munin::Master::Config->instance();

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
        my @services = $self->{node}->list_services();
        
        for my $service (@services) {
            if (%{$config->{limit_services}}) {
                next unless $config->{limit_services}{$service};
            }
            
            my %service_config = $self->_fetch_service_config($service);
            unless (%service_config) {
                logger("[WARNING] Service $service returned no config");
                next;
            }
            my %service_data = eval {
                $self->{node}->fetch_service_data($service);
            };
            if ($EVAL_ERROR) {
                logger($EVAL_ERROR);
                next;
            }

            $self->_update_rrd_files($service, \%service_config, \%service_data);
            $all_service_configs{$service} = \%service_config;
        }

        #use Data::Dumper; warn Dumper(\@services);
    });

    munin_removelock($lock_file);

    return {
        time_used => Time::HiRes::time - $update_time,
        service_configs => \%all_service_configs,
    }
}


sub _fetch_service_config {
    my ($self, $service) = @_;

    my %service_config = eval {
        $self->{node}->fetch_service_config($service);
    };
    if ($EVAL_ERROR) {
        # FIX Report failed service so that we can use the old service
        # config.
        logger($EVAL_ERROR);
        return;
    }

    if ($self->{host}{service_config} && $self->{host}{service_config}{$service}) {
        %service_config
            = (%service_config, %{$self->{host}{service_config}{$service}});
    }

    return %service_config;
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

    $data_source->{type} ||= 'GAUGE';
    $data_source->{min}  ||= 'U';
    $data_source->{max}  ||= 'U';
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

