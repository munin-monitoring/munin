package Munin::Master::Host;

use warnings;
use strict;

use Carp;


sub new {
    my ($class, $host_name, $group, $attributes) = @_;

    $attributes ||= {};

    my $self = {
        host_name => $host_name,
        group     => $group,
        %$attributes,
    };

    return bless $self, $class;
}


1;


__END__

=head1 NAME

Munin::Master::Host - Holds information on hosts we are interested in
collection data from. 

=head1 SYNOPSIS

FIX

=head1 DESCRIPTION

Note that a host and a node is not the same thing. FIX elaborate

=head1 METHODS

=over

=item B<new>

FIX

=back

