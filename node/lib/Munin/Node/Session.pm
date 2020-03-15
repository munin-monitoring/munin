package Munin::Node::Session;

use warnings;
use strict;


sub new {
    my ($class) = @_;

    my $self = {
        tls_started  => 0,
        peer_address => '',
        capabilities => {},
    };

    return bless $self, $class;
}


1;

__END__

=head1 NAME

Munin::Node::Session - Stores the state for the session between a node
and a master.


=head1 SYNOPSIS

 $session = Munin::Node::Session->new();
 $session->{capabilities} = { foo => 1, bar => 1};


=head1 METHODS

=over

=item B<new>

 $class->new();

Constructor.

=back

