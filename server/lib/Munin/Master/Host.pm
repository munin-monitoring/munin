package Munin::Master::Host;

use warnings;
use strict;

use Carp;


sub new {
    my ($class, $host_name, $attributes) = @_;

    $attributes ||= {};

    my $self = {
        host_name => $host_name,
        %$attributes,
    };

    return bless $self, $class;
}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX

