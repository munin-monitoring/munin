package Munin::Master::Worker;

use warnings;
use strict;

use Scalar::Util qw(refaddr);

sub new {
    my ($class, $identity) = @_;

    my $self = bless {}, $class;

    $identity = refaddr($self) unless defined $identity;
    $self->{ID} = $identity;

    return $self;
}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

