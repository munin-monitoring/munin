# -*- cperl -*-
use warnings;
use strict;

use Test::More 'no_plan';

use Data::Dumper;

require_ok('sbin/munin-node-configure');

use Munin::Node::Config;
my $config = Munin::Node::Config->instance();

my $PWD = POSIX::getcwd();

$config->reinitialize({
	libdir  => "$PWD/t/plugins",
	timeout => 10,
});


### fetch_plugin_autoconf
{
	my @tests = (
		[
			'bad-exit1',
			{ default => 'no' },
			'Plugin replied "no", but returns non-zero',	# FIXME: test for the error it emits!
		],
		[
			'bad-no-answer',
			{ default => 'no' },
			"Plugin exits without printing anything",
		],
		[
			'bad-cruft-stderr',
			{ default => 'no' },
			"Plugin replied 'yes', but with junk to stderr",
		],
		[
			'bad-signal',
			{ default => 'no' },
			"Plugin replied yes, but died due to a signal",
		],
		[
			'bad-timeout',
			{ default => 'no' },
			"Plugin timed out",
		],
	);
}


### fetch_plugin_suggest
{
	my @tests = (
		[
			'good',
			{
				default => 'yes',
				suggestions => [
					qw/one two three/
				],
			},
			"Plugin provided a list of valid suggestions",
		],
		[
			'good-no-autoconf',
			{ default => 'no' },
			"Plugin didn't pass autoconf",
		],
		[
			'bad-empty',
			{ suggestions => [], default => 'yes' },
			"Plugin provided no suggestions",
		],
		[
			'bad-illegal-chars',
			{
				default => 'yes',
				suggestions => [
					qw/one two/
				],
			},
			"Plugin produced a suggestion containing illegal characters",
		],
		[
			'bad-junk',
			{ suggestions => [], default => 'yes' },
			"Plugin wrote junk to stderr -- all suggestions voided",
		],
		[
			'bad-exit1',
			{ suggestions => [], default => 'yes' },
			"Plugin returned non-zero -- all suggestions voided",
		],

#		[
#			'',
#			{ suggestions => [], default => 'yes' },
#			"",
#		],
	);
}


### parse_snmpconf_response
{
	my @tests = (
		[
			[ 'require 1.3.6.1.2.1.25.2.2.0'   ],
			{
				require_oid => [
					[ '1.3.6.1.2.1.25.2.2.0', undef ],
				],
			},
			'Require - OID'
		],
		[
			[ 'require .1.3.6.1.2.1.25.2.2.0' ],
			{
				require_oid => [
					[ '.1.3.6.1.2.1.25.2.2.0', undef ],
				],
			},
			'Require - OID with leading dot'
		],
		[
			[ 'require 1.3.6.1.2.1.25.2.2.0  [0-9]' ],
			{
				require_oid => [
					[ '1.3.6.1.2.1.25.2.2.0', '[0-9]' ],
				],
			},
			'Require - OID with regex'
		],
		[
			[ 'require 1.3.6.1.2.1.2.2.1.5.   [0-9]' ],
			{
				require_root => [
					[ '1.3.6.1.2.1.2.2.1.5', '[0-9]' ],
				],
			},
			'Require - OID root with regex'
		],
		[
			[ 'require 1.3.6.1.2.1.2.2.1.5.', ],
			{
				require_root => [
					[ '1.3.6.1.2.1.2.2.1.5', undef ],
				],
			},
			'Require - OID root without regex'
		],
		[
			[
				'require 1.3.6.1.2.1.2.2.1.5.  [0-9]',
				'require 1.3.6.1.2.1.2.2.1.10.  ',
				'require 1.3.6.1.2.1.2.2.2.5   2',
			],
			{
				require_root => [
					[ '1.3.6.1.2.1.2.2.1.5', '[0-9]' ],
				  	[ '1.3.6.1.2.1.2.2.1.10', undef  ],
				],
				require_oid => [
					[ '1.3.6.1.2.1.2.2.2.5', '2' ],
				],
			},
			'Require - Multiple require statements'
		],
		[
			[ 'number  1.3.6.1.2.1.2.1.0', ],
			{
				number => '1.3.6.1.2.1.2.1.0',
			},
			'Number - OID'
		],
		[
			[ 'number  1.3.6.1.2.1.2.1.', ],
			{},
			'Number - OID root is an error'
		],
		[
			[ 'index 1.3.6.1.2.1.2.1.0', ],
			{},
			'Index - OID is an error'
		],
		[
			[ 'index   1.3.6.1.2.1.2.1.', ],
			{
				'index' => '1.3.6.1.2.1.2.1',
			},
			'Index - OID root'
		],
		[
			[
				'index	1.3.6.1.2.1.2.2.0.',
				'number 1.3.6.1.2.1.2.1.0  ',
				'', # blank line
				'require 1.3.6.1.2.1.2.2.2.5',
			],
			{
				require_oid => [
					[ '1.3.6.1.2.1.2.2.2.5', undef ],
				],
				number => '1.3.6.1.2.1.2.1.0',
				'index' => '1.3.6.1.2.1.2.2.0',
			},
			'Putting it all together'
		],

	#	[
	#		[ '', ],
	#		{},
	#		''
	#	],
	);

}


