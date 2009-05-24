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
		--paranoia
		--debug
		--pidebug
		plugin config
	);

	my ($plugin, $argument) = parse_args();

	is_deeply(
		$config,
		{
			conffile   => 'config_file',
			servicedir => 'service_directory',
			sconfdir   => 'service_config_directory',
			sconffile  => 'service_config_file',
			paranoia   => 1,
			DEBUG      => 1,
			PIDEBUG    => 1,
		},
		'Command-line arguments set the correct configuration items'
	);

	is($plugin, 'plugin', 'Plugin name is read from @ARGV');
	is($argument, 'config', 'Argument is read from @ARGV');

	@ARGV = qw(plugin bad_argument);

	($plugin, $argument) = parse_args();
	is($argument, undef, 'Invalid argument is ignored');
}


### merge_node_config
{
	$config->reinitialize({
		paranoia => 0,
		conffile => 't/config/munin-node.conf',
	});

	merge_node_config();

	is($config->{paranoia}, 0, 'Paranoia in arguments takes precedence over configuration file');

	delete $config->{paranoia};

	merge_node_config();

	is($config->{paranoia}, 1, 'Paranoia in configuration file takes precedence when --paranoia not set');
}


