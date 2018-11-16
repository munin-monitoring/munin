# -*- cperl -*-
use warnings;
use strict;

use English qw(-no_match_vars);
use Data::Dumper;

use Test::More qw(no_plan);

# use Test::More tests => 15;

use_ok('Munin::Master::Node');

my $node = bless { address => "127.0.0.1",
		   port => "4949",
		   host => "localhost" }, "Munin::Master::Node";

$INPUT_RECORD_SEPARATOR = '';
my @input = split("\n",<DATA>);

# print "Input: ",@input,"\n";

my %answer = $node->parse_service_config("Test", \@input);

=comment

# This is the old datastructure returned by parse_service_config.
# Kept here as a reference until multigraph is fully working. -janl 2009-10-23

my $fasit = {
          'data_source' => {
                             'system' => {
                                           'info' => 'CPU time spent by the kernel in system activities',
                                           'draw' => 'AREA',
                                           'min' => '0',
                                           'max' => '200',
					   'critical' => '100',
					   'warning' => '60',
                                           'label' => 'system',
                                           'type' => 'DERIVE'
                                         },
                             'user' => {
                                         'info' => 'CPU time spent by normal programs and daemons',
                                         'draw' => 'STACK',
                                         'min' => '0',
                                         'warning' => '160',
                                         'max' => '200',
                                         'type' => 'DERIVE',
                                         'label' => 'user'
                                       }
                           },
          'global' => [
                        [
                          'graph_title',
                          'CPU usage'
                        ],
                        [
                          'graph_order',
                          'system user nice idle iowait irq softirq'
                        ],
                        [
                          'graph_args',
                          '--base 1000 -r --lower-limit 0 --upper-limit 200'
                        ],
                        [
                          'graph_vlabel',
                          '%'
                        ],
                        [
                          'graph_scale',
                          'no'
                        ],
                        [
                          'graph_info',
                          'This graph shows how CPU time is spent.'
                        ],
                        [
                          'graph_category',
                          'system'
                        ],
                        [
                          'graph_period',
                          'second'
                        ]
                      ]
        };
=cut

my $fasit = {
          'data_source' => {
                             'Test' => {
                                         'system' => {
                                                       'info' => 'CPU time spent by the kernel in system activities',
                                                       'draw' => 'AREA',
                                                       'min' => '0',
                                                       'max' => '200',
                                                       'critical' => '100',
                                                       'warning' => '60',
                                                       'label' => 'system',
                                                       'type' => 'DERIVE'
                                                     },
                                         'user' => {
                                                     'info' => 'CPU time spent by normal programs and daemons',
                                                     'draw' => 'STACK',
                                                     'min' => '0',
                                                     'warning' => '160',
                                                     'max' => '200',
                                                     'type' => 'DERIVE',
                                                     'label' => 'user'
                                                   }
                                       }
                           },
          'global' => {
                        'multigraph' => [
                                          'Test'
                                        ],
                        'Test' => [
                                    [
                                      'graph_title',
                                      'CPU usage'
                                    ],
                                    [
                                      'graph_order',
                                      # Since 53f22440a the internal "graph_order" implementation
                                      # includes the list of data field appearances after the
                                      # explicitly configured graph_order.
                                      'system user nice idle iowait irq softirq system user'
                                    ],
                                    [
                                      'graph_args',
                                      '--base 1000 -r --lower-limit 0 --upper-limit 200'
                                    ],
                                    [
                                      'graph_vlabel',
                                      '%'
                                    ],
                                    [
                                      'graph_scale',
                                      'no'
                                    ],
                                    [
                                      'graph_info',
                                      'This graph shows how CPU time is spent.'
                                    ],
                                    [
                                      'graph_category',
                                      'system'
                                    ],
                                    [
                                      'graph_period',
                                      'second'
                                    ]
                                  ]
                      }
        };


is_deeply(\%answer,$fasit,"Plugin config output");

__DATA__
graph_title CPU usage
graph_order system user nice idle iowait irq softirq
graph_args --base 1000 -r --lower-limit 0 --upper-limit 200
graph_vlabel %
graph_scale no
graph_info This graph shows how CPU time is spent.
graph_category system
graph_period second
system.label system
system.draw AREA
system.max 200
system.min 0
system.type DERIVE
system.warning 60
system.critical 100
system.info CPU time spent by the kernel in system activities
user.label user
user.draw STACK
user.min 0
user.max 200
user.warning 160
user.type DERIVE
user.info CPU time spent by normal programs and daemons
