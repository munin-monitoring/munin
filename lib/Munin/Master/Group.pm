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

=item B<get_all_hosts>

  my @hosts = $group->get_all_hosts();

Returns the list of all hosts associated with this group, including those
belonging to any sub-groups.

=back

=cut
