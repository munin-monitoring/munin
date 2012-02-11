use warnings;
use strict;

use Test::More 'no_plan';

use_ok('Munin::Common::Config');

# cl_is_keyword
{
	ok(  Munin::Common::Config::cl_is_keyword('logdir'), 'valid keyword');
	ok(! Munin::Common::Config::cl_is_keyword('fnord'), 'invalid keyword');
}


# is_keyword
{
	ok(  Munin::Common::Config->is_keyword('logdir'), 'valid keyword');
	ok(! Munin::Common::Config->is_keyword('fnord'), 'invalid keyword');
}


# parse_config_from_file


# _trim
{
	# input parameter has to be a variable, as it gets modified directly by _trim
	my $s;

	Munin::Common::Config->_trim($s = '');
	is($s, '', 'empty line');

	Munin::Common::Config->_trim($s = '   ');
	is($s, '', 'only whitespace');

	Munin::Common::Config->_trim($s = ' leading whitespace');
	is($s, 'leading whitespace');

	Munin::Common::Config->_trim($s = 'trailing whitespace   ');
	is($s, 'trailing whitespace');

	Munin::Common::Config->_trim($s = '  both leading and trailing whitespace   ');
	is($s, 'both leading and trailing whitespace');
}


# _strip_comment
{
	# input parameter has to be a variable, as it gets modified directly by _strip_comment
	my $s;

	Munin::Common::Config->_strip_comment($s = '');
	is($s, '', 'empty line');

	Munin::Common::Config->_strip_comment($s = 'line without comment');
	is($s, 'line without comment');

	Munin::Common::Config->_strip_comment($s = 'line with a simple comment   ## here is the comment!');
	is($s, 'line with a simple comment   ');

	Munin::Common::Config->_strip_comment($s = 'line with an escaped \#  ');
	is($s, 'line with an escaped #  ');

	Munin::Common::Config->_strip_comment($s = 'line with a comment including an escaped hash # escaped \#  ');
	is($s, 'line with a comment including an escaped hash ');

	Munin::Common::Config->_strip_comment($s = 'line with a comment including two \# \## escaped \#  ');
	is($s, 'line with a comment including two # #');
}


# _looks_like_a_bool
{
	ok(  Munin::Common::Config->_looks_like_a_bool('yes'),   'yes');
	ok(  Munin::Common::Config->_looks_like_a_bool('Yes'),   'Yes');
	ok(  Munin::Common::Config->_looks_like_a_bool('no'),    'no');
	ok(  Munin::Common::Config->_looks_like_a_bool('NO'),    'NO');
	ok(  Munin::Common::Config->_looks_like_a_bool('1'),     'the number 1');
	ok(  Munin::Common::Config->_looks_like_a_bool('0'),     'the number 0');
	ok(  Munin::Common::Config->_looks_like_a_bool('true'),  'true');
	ok(  Munin::Common::Config->_looks_like_a_bool('false'), 'false');
	ok(  Munin::Common::Config->_looks_like_a_bool('on'),    'on');
	ok(  Munin::Common::Config->_looks_like_a_bool('off'),   'off');

	ok(! Munin::Common::Config->_looks_like_a_bool('falsch'), 'not a boolean');
	ok(! Munin::Common::Config->_looks_like_a_bool('yes!'),   'not a boolean either');
}


# _parse_bool
{
	ok(  Munin::Common::Config->_parse_bool('yes'),   'yes');
	ok(  Munin::Common::Config->_parse_bool('Yes'),   'Yes');
	ok(  Munin::Common::Config->_parse_bool('1'),     'the number 1');
	ok(  Munin::Common::Config->_parse_bool('true'),  'true');
	ok(  Munin::Common::Config->_parse_bool('on'),    'on');

	ok(! Munin::Common::Config->_parse_bool('no'),    'no');
	ok(! Munin::Common::Config->_parse_bool('NO'),    'NO');
	ok(! Munin::Common::Config->_parse_bool('false'), 'false');
	ok(! Munin::Common::Config->_parse_bool('off'),   'off');

	eval { Munin::Common::Config->_parse_bool('falsch') };
	like($@, qr/falsch/, 'exception on bad boolean');
}

