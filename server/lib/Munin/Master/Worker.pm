package Munin::Master::Worker;

use warnings;
use strict;

use Scalar::Util qw(refaddr);


use overload q{""} => 'to_string';


sub new {
    my ($class, $identity) = @_;

    my $self = bless {}, $class;

    $identity = refaddr($self) unless defined $identity;
    $self->{ID} = $identity;

    return $self;
}


sub to_string {
    my ($self) = @_;

    return sprintf("%s<%s>", ref $self, $self->{ID}); 
}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

