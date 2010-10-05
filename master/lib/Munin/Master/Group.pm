package Munin::Master::Group;

use base qw(Munin::Master::GroupRepository);

# $Id: Group.pm 2831 2009-11-03 23:32:48Z janl $

use warnings;
use strict;

use Carp;
use Munin::Master::Host;

sub new {
    my ($class, $group_name, $parent) = @_;

    my $self = {
        group_name => $group_name,
        hosts      => {},
    };

    return bless $self, $class;
}


sub add_attributes {
    my ($self, $attributes) = @_;

    my %valid_attributes = map {$_ => 1} qw(node_order local_address contacts);

    croak "Invalid attributes: " . join(', ', keys %$attributes)
        if grep { !$valid_attributes{$_} } keys %$attributes;

    %$self = (%$self, %$attributes);
}


sub add_host {
    my ($self, $host) = @_;

    $self->{hosts}{$host->{host_name}} = $host;
}


sub give_attributes_to_hosts {
    my ($self) = @_;

    my %not_inheritable = map {$_ => 1} qw(group_name hosts node_order);
    my %attributes = grep { !$not_inheritable{$_} } %$self;

    map { $_->add_attributes_if_not_exists(\%attributes) } values %{$self->{hosts}};

    return 1;
}


sub get_all_hosts {
    my ($self) = @_;

    my @hosts = ();

    for my $group (values %{$self->{groups}}) {
        push @hosts, $group->get_all_hosts;
    }

    push @hosts, values %{$self->{hosts}};
    
    return @hosts;
}

1;


__END__

=head1 NAME

Munin::Master::Group - Holds information on host groups.

=head1 SYNOPSIS

FIX

=head1 METHODS

=over 

=item B<new>

FIX

=item B<add_attributes>

FIX

=item B<add_host>

FIX

=item B<give_attributes_to_hosts>

FIX

=item B<get_all_hosts>

FIX

=back
