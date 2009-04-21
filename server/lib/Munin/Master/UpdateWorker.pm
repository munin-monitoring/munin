package Munin::Master::UpdateWorker;
use base qw(Munin::Master::Worker);

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
use RRDs;

my $config = Munin::Master::Config->instance();

sub new {
    my ($class, $host) = @_;

    my $self = $class->SUPER::new($host->{host_name});
    $self->{host} = $host;
    $self->{node} = Munin::Master::Node->new($host->{address},
                                             $host->{port},
                                             $host->{host_name});

    return $self;
}


sub do_work {
    my ($self) = @_;

    my $retval = {};

    $self->{node}->do_in_session(sub {
        $self->{node}->negotiate_capabilities();
        my @services = $self->{node}->list_services();
        
        for my $service (@services) {
            my %service_config = eval {
                $self->{node}->fetch_service_config($service);
            };
            if ($EVAL_ERROR) {
                logger($EVAL_ERROR);
                # FIX use old config if exists, else stop all further
                # processing of service
            }

            use Data::Dumper; warn Dumper(\%service_config);

            $self->_create_rrd_files_if_needed($service, $service_config{data_source});

            my @service_data = eval {
                $self->{node}->fetch_service_data($service);
            };
            if ($EVAL_ERROR) {
                logger($EVAL_ERROR);
                next;
            }

            use Data::Dumper; warn Dumper(\@service_data);
        }

        $retval->{services} = \@services;
    });

    return $retval;
}


sub _create_rrd_files_if_needed {
    my ($self, $service, $data_sources) = @_;

    for my $ds_name (keys %$data_sources) {
        $data_sources->{$ds_name}{type} ||= 'GAUGE';
        $data_sources->{$ds_name}{min}  ||= 'U';
        $data_sources->{$ds_name}{max}  ||= 'U';

        my $rrd_file = $self->_get_rrd_file_name($service, $ds_name, $data_sources->{$ds_name});
        unless (-f $rrd_file) {
            $self->_create_rrd_file($rrd_file, $service, $ds_name, $data_sources->{$ds_name});
        }
    }
}


sub _get_rrd_file_name {
    my ($self, $service, $ds_name, $ds_config) = @_;
    
    # FIX escape silly characters

    my $type_id = lc(substr(($ds_config->{type}), 0, 1));
    my $file = sprintf("%s.%s-%s-%s-%s.rrd",
                       $self->{host}{host_name},
                       $self->{host}{group}{group_name},
                       $service,
                       $ds_name,
                       $type_id);

    return File::Spec->catfile($config->{dbdir}, 
                               $self->{host}{group}{group_name},
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
            
    my $resolution = 'normal';     #FIX &munin_get ($fhash, "graph_data_size", "normal");
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

