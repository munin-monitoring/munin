use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;

require_ok( 'Munin::Master::Update' );
require_ok( 'Munin::Master::Config' );

# Launch minimal test nodes with spoolfetch support
use File::Basename;
my $script_dir = dirname(__FILE__);
my $test_node = "$script_dir/lib/node_test_spool.pl";
my @pids;

for my $port (24949, 24950, 24951) {
    my $pid = fork();
    if ($pid == 0) {
        exec("perl", $test_node, $port, "30");
        die "exec failed: $!";
    }
    push @pids, $pid;
}

# Wait for nodes to start
sleep(1);

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
sleep(2);

ok($update->run() == 5);

kill('TERM', @pids);
wait();

done_testing();

1;
