package Munin::Master::GroupRepository;

use base qw(Munin::Master::Config);

use warnings;
use strict;

use Carp;
use Log::Log4perl qw( :easy );


sub new {
    # This is now a container class used on some entries in the
    # Munin::Master::Config instance.  It used to be a
    # self-contained, self-booting class instantiator.

    my ($class, $gah) = @_;
    my $self = bless {}, $class;

    # $gah is usually a pointer to
    # Munin::Master::Config->instance()->{config}{groups};

    $self->{groups} = $gah;

    return $self;
}

1;

__END__

=head1 NAME

Munin::Master::GroupRepository - FIX

=head1 METHODS

Inherits methods from Munin::Master::Config.

=over

=item B<new>

  my $gr = Munin::Master::GroupRepository->new($groups_and_hosts);

Constructor.  $groups_and_hosts is the list of groups and hosts to associate
with the instance.  (This will usually be
C<< Munin::Master::Config->instance()->{config}{groups}; >>

=back

=cut
# vim: ts=4 : sw=4 : et
