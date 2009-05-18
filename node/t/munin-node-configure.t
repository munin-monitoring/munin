use warnings;
use strict;

use Test::More tests => 7;

require_ok('sbin/munin-node-configure');

use Munin::Node::Config;
my $config = Munin::Node::Config->instance();


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

