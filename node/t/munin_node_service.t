use warnings;
use strict;

use Test::More tests => 2;

use_ok('Munin::Node::Service');

my $config = Munin::Node::Config->instance();


### export_service_environment

{
	$config->reinitialize({
		sconf => {
			test => {
				env => {
					test_environment_variable => 'fnord'
				}
			}
		}
	});

	Munin::Node::Service->export_service_environment('test');
	is($ENV{test_environment_variable}, 'fnord', 'Service-specific environment is exported');
}


