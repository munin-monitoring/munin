package Munin::Common::TLSServer;
use base qw(Munin::Common::TLS);

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);

sub new {
    my ($class, $args) = @_;

    return $class->SUPER::new($args);
}


sub start_tls {
    my ($self) = @_;

    $self->SUPER::_start_tls();
}


sub _initial_communication {
    my ($self) = @_;

    if ($self->{private_key_loaded}) {
        $self->{write_func}("TLS OK\n");
    }
    else {
        $self->{write_func}("TLS MAYBE\n");
    }
            
    return 1;
}


sub _use_key_if_present {
    my ($self) = @_;

    return $self->{private_key_loaded};
}


1;

__END__


=head1 NAME

Munin::Node::TLSServer - Implements the server side of the STARTTLS protocol


=head1 SYNOPSIS

 # After receiving a STARTTLS request:

 $tls = Munin::Node::TLSServer->new(...);
 $tls->start_tls();

=head1 METHODS

=over

=item B<new>

 $tls = Munin::Node::TLSServer->new(...);

See L<Munin::Node::TLS> for documentation for constructor arguments.

=item B<start_tls>

 $tls->start_tls();

Process a STARTTLS request

=back
