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


sub add_attributes_if_not_exists {
    my ($self, $attributes) = @_;

    %$self = (%$attributes, %$self);
}


sub get_canned_ds_config {
    my ($self, $service, $data_source) = @_;

    # XXX: Could this be done in some sane way?

    my %ds_config;
    my $svc_ds_prefix = "$service.$data_source.";

    for my $svc_ds_prop (keys %$self) {
        if (index($svc_ds_prop, $svc_ds_prefix) == 0) {
            my $prop = substr($svc_ds_prop, length($svc_ds_prefix));
            $ds_config{$prop} = $self->{$svc_ds_prop};
        }
    }

    return \%ds_config;
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

=item B<add_attributes_if_not_exists>

  $host->add_attributes_if_not_exists(\%attrs);

Merges the new attributes from %attrs into the host object, without
overwriting any existing   

=item B<get_canned_ds_config>

FIX

=back

