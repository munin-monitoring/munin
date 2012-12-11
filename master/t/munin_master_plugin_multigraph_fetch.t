# -*- cperl -*-
# vim: ts=4 : sw=4 : et
use warnings;
use strict;

use English qw(-no_match_vars);
use Data::Dumper;

use Test::More tests => 2;

use_ok('Munin::Master::Node');

# use_ok('Munin::Master::Logger');
# logger_debug();

# Mock object enough to be able to call (some) object methods.
my $node = bless { address => "127.0.0.1",
		   port => "4949",
		   host => "localhost" }, "Munin::Master::Node";

$INPUT_RECORD_SEPARATOR = '';
my @input = split("\n",<DATA>);

# make time() return a known value.
BEGIN { *CORE::GLOBAL::time = sub { 1234567890 }; }
my $time = time;

my %answer = $node->parse_service_data("multigraph_tester", \@input);


# Output captured from Data::Dumper
my $fasit = {
    'multigraph_outofscope' => {
        i => {
            when  => [ $time ],
            value => [ 42    ],
        }
    },
    'multigraph_tester' => {
        three => {
            when  => [ $time ],
            value => [ 3     ],
        },
        one => {
            when  => [ $time ],
            value => [ 1     ],
        },
        two => {
            when  => [ 1256305817 ],
            value => [ 2          ],
        }
    },
    'multigraph_tester.en' => {
        one => {
            when  => [ 1256305817 ],
            value => [ 1          ],
        }
    },
    'multigraph_tester.to' => {
        two => {
            when  => [ $time ],
            value => [ 2     ],
        }
    },
    'multigraph_tester.tre' => {
        three => {
            when  => [ $time ],
            value => [ 3     ],
        }
    }
};

# print Dumper \%answer;

is_deeply(\%answer, $fasit, 'Multigraph plugin fetch output');


__DATA__
one.value 1
two.value 1256305817:2
three.value 3
#
multigraph multigraph_tester.en
one.value 1256305817:1
#
multigraph multigraph_tester.to
two.value 2
#
multigraph multigraph_tester.tre
three.value 3
#
multigraph multigraph_outofscope
i.value 42
