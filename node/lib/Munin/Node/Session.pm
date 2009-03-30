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

Munin::Node::Session - FIX


=head1 SYNOPSIS

FIX


=head1 METHODS

=over

=item B<new>

 $class->new();

FIX

=back

