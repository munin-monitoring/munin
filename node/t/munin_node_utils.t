use strict;
use warnings;

use Test::More 'no_plan';

use Munin::Node::Utils;


### _set_complement
### _set_intersection
{
    my @tests = (
        [
            [ [qw/a b c/], [qw/a b c/] ], [ [], [qw/a b c/] ],
            'Equal sets',
        ],
        [
            [ [qw/a b c/], [qw/d e f/] ], [ [qw/a b c/], [] ],
            'Disjoint sets',
        ],
        [
            [ [qw/a b c/], [qw/c d e/] ], [ [qw/a b/], [qw/c/] ],
            'Intersecting sets',
        ],
        [
            [ [], [qw/a b c/] ], [ [], [] ],
            'First set is empty',
        ],
        [
            [ [qw/a b c/], [] ], [ [qw/a b c/], [] ],
            'Second set is empty',
        ],
        [
            [ [], [] ], [ [], [] ],
            'Both sets are empty',
        ],
    );

    foreach (@tests) {
        my ($sets, $expected, $msg) = @$_;
        is_deeply(
            [ Munin::Node::Utils::set_difference(@$sets) ],
            $expected->[0],
            "$msg - complement"
        );
        is_deeply(
            [ Munin::Node::Utils::set_intersection(@$sets) ],
            $expected->[1],
            "$msg - intersection"
        );
    }
}


