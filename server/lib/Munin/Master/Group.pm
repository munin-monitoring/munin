package Munin::Master::Group;

use warnings;
use strict;

use Carp;
use Munin::Master::Host;


sub new {
    my ($class, $group_name, $parent) = @_;

    my $self = {
        group_name => $group_name,
        hosts      => {},
        groups     => {},
    };

    return bless $self, $class;
}


sub add_attributes {
    my ($self, $attributes) = @_;

    %$self = (%$self, %$attributes);
}


sub add_host {
    my ($self, $host) = @_;

    $self->{hosts}{$host->{host_name}} = $host;
}


sub get_all_hosts {
    my ($self) = @_;
    
    my @hosts = ();
    for my $group (values %{$self->{groups}}) {
        push @hosts, $group->get_all_hosts();
    }
                   
    return (values %{$self->{hosts}}, @hosts);
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

=item B<get_all_hosts>

FIX

=back
