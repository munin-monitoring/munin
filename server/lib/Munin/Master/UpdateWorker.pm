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

    $self->{node}->session(sub {
        my @capabilities = $self->{node}->negotiate_capabilities();
        my @services     = $self->{node}->list_services();
        
        for my $service (@services) {
            eval {
                my %service_config = $self->{node}->fetch_service_config($service);
                use Data::Dumper; warn Dumper(\%service_config);

            };
            if ($EVAL_ERROR) {
                # FIX use old config if exists, else stop all further
                # processing og service
            }

        }

        $retval->{services}     = \@services;
        $retval->{capabilities} = \@capabilities;
    });

    return $retval;
}


sub _run_starttls_if_required {}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

