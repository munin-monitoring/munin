# -*- cperl -*-
use warnings;
use strict;

use Test::More 'no_plan';

use POSIX ();
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


