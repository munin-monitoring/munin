use strict;
use warnings;

use lib qw(t/lib);


use Test::More;

require_ok( 'Munin::Master::Update' );
require_ok( 'Munin::Master::Config' );

# Launch node-debug
my $pid_debug_node = 0;
unless (($pid_debug_node = fork())) {
	exec("contrib/munin-node-debug", "--spoolfetch", "--starting-epoch", (time - 600));
}

# Wait for the node to start
sleep(5);

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file("t/config/munin.conf");

$config->{dbdir} .= "/update-spoolfetch/$$";

system("mkdir", "-p", $config->{dbdir});

Munin::Common::Logger::configure(
	"output" => "screen",
	"level" => "info",
);


my $update = Munin::Master::Update->new();
ok($update->run() == 5);

# Run a second time, with an already populated database
ok($update->run() == 5);

# Run a third time, but wait for some more data to arrive
sleep(60);

ok($update->run() == 5);

kill('TERM', $pid_debug_node);
wait();

done_testing();

1;
