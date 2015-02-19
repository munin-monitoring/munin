# -*- cperl -*-
use warnings;
use strict;

use English qw(-no_match_vars);
use Data::Dumper;

# use Test::More qw(no_plan);
use Test::More tests => 2;

use_ok('Munin::Master::Node');

my $node = bless { address => "127.0.0.1",
		   port => "4949",
		   host => "localhost" }, "Munin::Master::Node";

$INPUT_RECORD_SEPARATOR = '';
my @input = split("\n",<DATA>);

# make time() return a known-good value.
BEGIN { *CORE::GLOBAL::time = sub { 1234567890 }; }
my $time = time;

my %answer = $node->parse_service_data("cpu", \@input);

=comment

Keep old correct answer for reference.

my $fasit = {
          'irq' => {
                     'when' => '1256305015',
                     'value' => '2770'
                   },
          'system' => {
                        'when' => 'N',
                        'value' => '66594'
                      },
          'softirq' => {
                         'when' => '1256305015',
                         'value' => '127'
                       },
          'user' => {
                      'when' => 'N',
                      'value' => '145923'
                    },
          'idle' => {
                      'when' => 'N',
                      'value' => '2245122'
                    },
          'iowait' => {
                        'when' => 'N',
                        'value' => '14375'
                      },
          'nice' => {
                      'when' => 'N',
                      'value' => '268'
                    }
        };

=cut

my $fasit = {
    cpu => {
        irq => {
            when  => [ 1256305015 ],
            value => [ 2770       ],
        },
        system => {
            when  => [ $time ],
            value => [ 66594 ],
        },
        softirq => {
            when  => [ 1256305015 ],
            value => [ 127        ],
        },
        user => {
            when  => [ $time  ],
            value => [ 145923 ],
        },
        iowait => {
            when  => [ $time ],
            value => [ 14375 ],
        },
        idle => {
            when  => [ $time   ],
            value => [ 2245122 ],
        },
        nice => {
            when  => [ $time ],
            value => [ 268   ],
        },
    },
};

is_deeply(\%answer,$fasit,"Plugin fetch output");

__DATA__
user.value 145923
nice.value 268
system.value 66594
idle.value 2245122
iowait.value 14375
irq.value 1256305015:2770
softirq.value 1256305015:127
