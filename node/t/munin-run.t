use warnings;
use strict;

use Test::More tests => 7;

require_ok('sbin/munin-run');

use Munin::Node::Config;
my $config = Munin::Node::Config->instance();

### parse_args

# check all the various parameters are set correctly in $config
{
	$config->reinitialize({});

	local @ARGV = qw(
		--config     config_file
		--servicedir service_directory
		--sconfdir   service_config_directory
		--sconffile  service_config_file
		--debug
		--paranoia
		--pidebug
		plugin config
	);

	my ($plugin, $argument) = parse_args();

	is_deeply(
		$config,
		{
			conffile   => 'config_file',
			sconfdir   => 'service_config_directory',
			sconffile  => 'service_config_file',
			paranoia   => 1,
			DEBUG      => 1,
		},
		'Command-line arguments set the correct configuration items'
	);

	is($plugin, 'plugin', 'Plugin name is read from @ARGV');
	is($argument, 'config', 'Argument is read from @ARGV');
}
{
	local @ARGV = qw(plugin);
	my ($plugin, $argument) = parse_args();
	is($argument, undef, 'No argument was given');
}
{
	local @ARGV = ('plugin', 'bad#argument');
	eval { parse_args() };
	like($@, qr/bad#argument/, 'Invalid argument causes a fatal error');
}
{
	local @ARGV = qw(plugin update);
	my ($plugin, $argument) = parse_args();
	is($argument, 'update', 'Unknown argument is ok');
}


