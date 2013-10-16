# -*- cperl -*-
# vim: ts=4 : sw=4 : et
use warnings;
use strict;

use Test::More tests => 3;
use Test::MockModule;

my $mock = Test::MockModule->new('RRDs');
$mock->mock('errors' => sub { });

use_ok('Munin::Master::GraphOld', qw(build_sum_cdef));

# It should be considered to move the RRDTool compatibility mechanisms into a centralized
# module.
my $AddNAN = "+";
if ($RRDs::VERSION >= 1.3) {
    $AddNAN = 'ADDNAN';
}
is(build_sum_cdef("a", "b", "c"), ",a,$AddNAN,b,$AddNAN", ".sum with >= 2 values");
is(build_sum_cdef("a"), "", ".sum with = 1 value");

# This test makes sure that both single value sums behave as expected (by
# just returning that one value) and multiple value sums behave as before. 
#
# Rationale:
#   Our hosts have multiple instances of the same service. Each instance has
#   it's own status graph and we aggregate these status graphs into a single 
#   host status graph.
#   However, it is quite a pain to work around hosts with one instance of 
#   a single instance, because "total.sum value_of_instance1" tended to output
#   invalid CDEFs and thus, rrdtool balked.
