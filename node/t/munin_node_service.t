use warnings;
use strict;

use Test::More tests => 6;

use_ok('Munin::Node::Service');

my $config = Munin::Node::Config->instance();

$config->reinitialize({
	timeout => 10,
	servicedir => '/service/directory',
	sconf => {
		test => {
			env => {
				test_environment_variable => 'fnord'
			}
		}
	}
});

### export_service_environment

{
	Munin::Node::Service->export_service_environment('test');
	is($ENV{test_environment_variable}, 'fnord', 'Service-specific environment is exported');
}


### is_a_runnable_service

### export_service_environment

### change_real_and_effective_user_and_group

### exec_service


### _service_command
{
	my ($plugin, $argument) = ('test', 'config');

	$config->{sconf}{test}{command} = undef;
	is_deeply(
		[ Munin::Node::Service::_service_command($plugin, $argument) ],
		[ "/service/directory/$plugin", $argument ],
		'No custom service command.'
	);

	$config->{sconf}{test}{command} = [ qw/a b c d/ ];
	is_deeply(
		[ Munin::Node::Service::_service_command($plugin, $argument) ],
		[ qw/a b c d/ ],
		'Custom service command without substitution.'
	);

	$config->{sconf}{test}{command} = [ qw/a b %c d/ ];
	is_deeply(
		[ Munin::Node::Service::_service_command($plugin, $argument) ],
		[ 'a', 'b', "/service/directory/$plugin", $argument, 'd' ],
		'Custom service command with substitution.'
	);
}

### fork_service
{
	my $ret = Munin::Node::Service->fork_service('foo');
	is($ret->{retval} >> 8, 42, 'Attempted to run non-existant service');
}


