use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 27;

use_ok('Munin::Plugin');

is(scaleNumber(1000000000000000000000000000000000,"bps","no "),     '1000000000.0Ybps');
is(scaleNumber(1000000000000000000000000000000,"bps","no "),        '1000000.0Ybps');
is(scaleNumber(1000000000000000000000000000,"bps","no "),           '1000.0Ybps');
is(scaleNumber(1000000000000000000000000,"bps","no "),              '1.0Ybps');
is(scaleNumber(1000000000000000000000,"bps","no "),                 '1.0Zbps');
is(scaleNumber(1000000000000000000,"bps","no "),                    '1.0Ebps');
is(scaleNumber(1000000000000000,"bps","no "),                       '1.0Pbps');
is(scaleNumber(1000000000000,"bps","no "),                          '1.0Tbps');
is(scaleNumber(1000000000,"bps","no "),                             '1.0Gbps');
is(scaleNumber(1000000,"bps","no "),                                '1.0Mbps');
is(scaleNumber(1000,"bps","no "),                                   '1.0kbps');
is(scaleNumber(1,"bps","no "),                                      '1.0bps');
is(scaleNumber(0.9999,"bps","no "),                                 '999.9mbps');
is(scaleNumber(0.1,"bps","no "),                                    '100.0mbps');
is(scaleNumber(0.001,"bps","no "),                                  '1.0mbps');
is(scaleNumber(0.000001,"bps","no "),                               '1.0ubps');
is(scaleNumber(0.000000001,"bps","no "),                            '1.0nbps');
is(scaleNumber(0.000000000001,"bps","no "),                         '1.0pbps');
is(scaleNumber(0.000000000000001,"bps","no "),                      '1.0fbps');
is(scaleNumber(0.000000000000000001,"bps","no "),                   '1.0abps');
is(scaleNumber(0.000000000000000000001,"bps","no "),                '1.0zbps');
is(scaleNumber(0.000000000000000000000001,"bps","no "),             '1.0ybps');
is(scaleNumber(0.000000000000000000000000001,"bps","no "),          'no ');
is(scaleNumber(0.000000000000000000000000000001,"bps","no "),       'no ');
is(scaleNumber(0.000000000000000000000000000000001,"bps","no "),    'no ');
is(scaleNumber(0.000000000000000000000000000000000001,"bps","no "), 'no ');
