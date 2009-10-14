package Munin::Master::Host;

use base qw(Munin::Master::Group);

# $Id$

use warnings;
use strict;

use Carp;

sub new {
    my ($class, $host_name, $group, $attributes) = @_;

    $attributes ||= {};

    my $self = {
        host_name => $host_name,
        group     => $group,

        port          => 4949,
        update        => 1,
        use_node_name => 1,
        
        %$attributes,
    };

    # "Address" is required but must be lazy about it.
    # die "Attribute 'address' is required for $host_name, config line $.\n" unless $self->{address};

    return bless $self, $class;
}


sub add_attributes_if_not_exists {
    my ($self, $attributes) = @_;

    %$self = (%$attributes, %$self);
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

=item B<add_attributes_if_not_exists>

FIX

=back

