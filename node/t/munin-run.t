use warnings;
use strict;

package Munin::Test;

use Test::More tests => 4;

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
		plugin
	);

	parse_args();

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


