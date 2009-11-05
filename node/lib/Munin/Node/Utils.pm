package Munin::Node::Utils;

# Various utility functions


### Set operations #############################################################

# returns the list of elements in arrayref $a that are not in arrayref $b
# NOTE this is *not* a method.
sub set_difference
{
    my ($A, $B) = @_;
    my %set;
    @set{@$A} = ();
    delete @set{@$B};
    return sort keys %set;
}


# returns the list of elements common to arrayrefs $a and $b
# NOTE this is *not* a method.
sub set_intersection
{
    my ($A, $B) = @_;
    my %set;
    @set{@$A} = (1) x @$A;
    return sort grep $set{$_}, @$B;
}


1;
