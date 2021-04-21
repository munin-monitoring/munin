package Munin::Master::Host;

use base qw(Munin::Master::Group);


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
        use_node_name => 0,

        %$attributes,
    };

    # "Address" is required but must be lazy about it.
    # die "Attribute 'address' is required for $host_name, config line $.\n" unless $self->{address};

    return bless $self, $class;
}


sub get_full_path {
    # Find the full nested named path of the current host object
    # might one for M::M::Group too and make it recursive instead of
    # "just" iterative but not now.

    my ($self) = @_;

    my $group;
    my @groups = ( $self->{host_name} );

    $group=$self->{group};
    while (defined($group)) {
	unshift(@groups,$group->{group_name});
	$group=$group->{group};
    }

    return join(";",@groups);
}

1;


__END__

=head1 NAME

Munin::Master::Host - Holds information on hosts we are interested in
collecting data from.

=head1 DESCRIPTION

NOTE that a host and a node are not the same thing -- some hosts may
report services for several nodes, for example if they have SNMP plugins
installed.

=head1 METHODS

=over

=item B<new>

  my $host = Munin::Master::Host->new($hostname, $group, \%attrs);

Constructor.  C<$group> is the C<Munin::Master::Group> object this host
belongs to.  Valid attributes include C<port>, C<update>, and
c<use_node_name>.

=item B<get_full_path>

Returns the full nested named path of the host object (eg. "group1;group2;hostname").

=back

