# -*- cperl -*-
use warnings;
use strict;

use English qw(-no_match_vars);
use Data::Dumper;

use Test::More qw(no_plan);

# use Test::More tests => 15;

use_ok('Munin::Master::Node');

use_ok('Munin::Master::Logger');
logger_debug();

my $node = bless {}, "Munin::Master::Node";

$INPUT_RECORD_SEPARATOR = '';
my @input = split("\n",<DATA>);

# print "Input: ",@input,"\n";

my %answer = $node->parse_service_config("Test",@input);

print Dumper \%answer;

# is_deeply(\%answer,$fasit,"Plugin config output");

__DATA__
graph_title Root graph of multigraph test
graph_info The root graph is used to click into sub-graph page.  Eventually the root graph should be able to borrow data from the sub graphs in a fairly easy manner.  But not right now.
one.label number 1
two.label number 2
three.label number 3
#
multigraph multigraph_tester.en
graph_title The number 1 sub-graph
graph_info This and the other . (dot) separated nested graphs are presented in a page linked to from the root graph
one.label number 1
#
multigraph multigraph_tester.to
graph_title The number 2 sub-graph
two.label number 2
#
multigraph multigraph_tester.tre
graph_title The number 3 sub-graph
three.label number 3
#
multigraph multigraph_outofscope
graph_title The out of namespace graph
graph_info The "multigraph protocol keyword allows the plugin to place data anywhere in the host/node namespace.  The intended use is to be able to produce multiple root graphs and sub-graph spaces, but this is not enforced.
i.label number i
