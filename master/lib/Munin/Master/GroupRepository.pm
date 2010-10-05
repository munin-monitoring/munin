package Munin::Master::GroupRepository;

use base qw(Munin::Master::Config);

# $Id: GroupRepository.pm 2831 2009-11-03 23:32:48Z janl $

use warnings;
use strict;

use Carp;
# use Munin::Master::Group;
# use Munin::Master::Host;
use Log::Log4perl qw( :easy );

sub new {
    # This is now a container class used on some entries in the
    # Munin::Master::Config::instance hash.  It used to be a
    # self-contained, self-booting class instanciator.

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

=head1 SYNOPSIS

FIX

=head1 METHODS

=over

=item B<new>

FIX

=item B<get_all_hosts>

FIX

=back

