package Munin::Master::Group;

use base qw(Munin::Master::GroupRepository);

use warnings;
use strict;

use Carp;
use Munin::Master::Host;

sub new {
    my ($class, $group_name) = @_;

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

Groups can be nested.

=head1 METHODS

=over

=item B<new>

  my $group = Munin::Master::Group->new($name, $parent);

Constructor.  $name is the name of the group.

=item B<add_attributes>

  $group->add_attributes(\%attrs);

Sets attributes %attrs for the group.  Valid attributes are:

=over 4

=item node_order

Override the order of the hosts within the group.

=item local_address

The local address the update process should bind to when contacting the nodes
in this group.

=item contacts

The contacts for this group.  See L<http://munin-monitoring.org/wiki/HowToContact>.

=back

An exception will be thrown if invalid attributes are provided.

(Full details here: L<http://munin-monitoring.org/wiki/munin.conf#Groupleveldirectives>.)

=item B<add_host>

  $group->add_host($host);

Adds host $host to the group.

=item B<give_attributes_to_hosts>

  $group->give_attributes_to_hosts();

Propagates the attributes of $group to all hosts in the group.  (This does
B<not> apply to hosts belonging to sub-groups.)

=item B<get_all_hosts>

  my @hosts = $group->get_all_hosts();

Returns the list of all hosts associated with this group, including those
belonging to any sub-groups.

=back

=cut
# vim: ts=4 : sw=4 : et
