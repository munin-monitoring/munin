package Munin::Master::UpdateWorker;
use base qw(Munin::Master::Worker);

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use Munin::Master::Node;

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
        my @capabilities = $self->{node}->negotiate_capabilities();
        my @services     = $self->{node}->list_services();
        
        for my $service (@services) {
            eval {
                my %service_config = $self->{node}->fetch_service_config($service);
                use Data::Dumper; warn Dumper(\%service_config);

            };
            if ($EVAL_ERROR) {
                # FIX Log it, use old config if exists, else stop all further
                # processing of service
            }

            eval {
                my @service_data = $self->{node}->fetch_service_data($service);
                use Data::Dumper; warn Dumper(\@service_data);
            };
            if ($EVAL_ERROR) {
                # FIX log the error, stop all further processing of
                # service
            }
        }

        $retval->{services}     = \@services;
        $retval->{capabilities} = \@capabilities;
    });

    return $retval;
}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

