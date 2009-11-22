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


# _strip_comment


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

