use warnings;
use strict;

use Test::More tests => 37;

use_ok('Munin::Plugin');

### clean_fieldname
my $valid = qr/^[A-Za-z_][A-Za-z0-9_]+$/;

# good
like(clean_fieldname('abcDEF123'), $valid);
# start with bad characters
like(clean_fieldname('1bcde'), $valid);
like(clean_fieldname('!bcde'), $valid);
# bad characters throughout
like(clean_fieldname('/abc/def'), $valid);


### _{encode,decode}_string
my @strings = (
	'abcde',
	'abc123DEF',
	"1234\n1234",
	'12% of my dinner',
	"\0\x{263a}",
);

is(Munin::Plugin::_decode_string(Munin::Plugin::_encode_string($_)),
	$_, 'string encode -> decode round-trip') foreach (@strings);


### _{encode,decode}_state
is_deeply(
	[ Munin::Plugin::_decode_state(Munin::Plugin::_encode_state(@strings)) ],
	\@strings,
	'state encode -> decode round-trip'
);


### scaleNumber

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



