package Munin::Node::Utils;


use strict;
use warnings;

use Exporter ();
our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/
	set_difference
	set_intersection
/;


### Set operations #############################################################

sub set_difference
{
    my ($A, $B) = @_;
    my %set;
    @set{@$A} = ();
    delete @set{@$B};
    my @tmp = sort keys %set;
    return @tmp;
}


sub set_intersection
{
    my ($A, $B) = @_;
    my %set;
    @set{@$A} = (1) x @$A;
    my @tmp = sort grep $set{$_}, @$B;
    return @tmp;
}


1;

__END__


=head1 NAME

Munin::Node::Utils - Various utility functions


=head1 SYNOPSIS

  use Munin::Node::Utils qw( ... );


=head1 SUBROUTINES

=over

=item B<set_difference(\@a, \@b)>

Returns the list of elements in arrayref \@a that are not in arrayref \@b.


=item B<set_intersection(\@a, \@b)>

Returns the list of elements common to arrayrefs \@a and \@b.

=back

=cut
