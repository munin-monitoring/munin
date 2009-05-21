use warnings;
use strict;

use Test::More tests => 14;

require_ok('sbin/munin-node-configure');

use Munin::Node::Config;
my $config = Munin::Node::Config->instance();

my $PWD = POSIX::getcwd();

$config->reinitialize({
	libdir => "$PWD/t/plugins",
});


### diff_suggestions
{
	my @tests = (
		# installed, suggested,
		# expected results (same, add, remove)
		# test description
		[
			[qw/a b c/], [qw/a b c/],
			[ [qw/a b c/], [], [] ],
			'All the suggestions are already installed',
		],
		[
			[qw//], [qw/a b c/],
			[ [], [qw/a b c/], [] ],
			'None of the suggestions are currently installed',
		],
		[
			[qw/a b c/], [],
			[ [], [], [qw/a b c/] ],
			'No suggestions offered (remove all)',
		],
		[
			[qw/a b/], [qw/a b c/],
			[ [qw/a b/], [qw/c/], [] ],
			'Some plugin identities to be added',
		],
		[
			[qw/a b c/], [qw/a b/],
			[ [qw/a b/], [], [qw/c/] ],
			'Some plugin identities to be removed',
		],
		[
			[qw/a b c d e/], [qw/c d e f g/],
			[ [qw/c d e/], [qw/f g/], [qw/a b/] ],
			'Some plugin identities to be added, some removed, some common.',
		],

#		[
#			[qw//], [qw//],
#			[ [qw//], [qw//], [qw//] ],
#			'',
#		],
	);

	while (my $test = shift @tests) {
		my ($installed, $suggested, $expected, $msg) = @$test;
		is_deeply(
			[diff_suggestions($installed, $suggested)],
			$expected,
			$msg
		);
	}

}



### fetch_plugin_autoconf
{
	my @tests = (
		[
			'good-yes',
			{ default => 'yes', defaultreason => undef },
			'Plugin autoconf replied "yes"'
		],
		[
			'good-no',
			{ default => 'no', defaultreason => undef },
			'Plugin autoconf replied "no"'
		],
		[
			'good-no-with-reason',
			{ default => 'no', defaultreason => 'just a test plugin' },
			'Plugin autoconf replied "no", and gives a reason'
		],
		[
			'bad-exit1',
			{ default => 'no', defaultreason => undef },
			'Plugin replied "no", but returns non-zero',	# FIXME: test for the error it emits!
		],
		[
			'bad-no-answer',
			{ default => 'no', defaultreason => undef },
			"Plugin doesn't print any recognised response",
		],
		[
			'bad-cruft',
			{ default => 'no', defaultreason => undef },
			"Plugin replied 'yes', but with junk",
		],
		[
			'bad-cruft-stderr',
			{ default => 'no', defaultreason => undef },
			"Plugin replied 'yes', but with junk to stderr",
		],

#		[
#			'',
#			{ default => '', defaultreason => undef },
#			"",
#		],
	);

	while (my $test = shift @tests) {
		my ($name, $expected, $msg) = @$test;

		my $plugin = { name => "autoconf-$name" };
		fetch_plugin_autoconf($plugin);

		# we know the name is right, and this saves having to mess with 
		# $expected
		delete $plugin->{name};

		is_deeply($plugin, $expected, $msg);
	}
}

