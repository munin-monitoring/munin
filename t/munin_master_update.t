use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;

require_ok( 'Munin::Master::Update' );
require_ok( 'Munin::Master::Config' );

# Launch minimal test nodes on ports 24949-24951
use File::Basename;
my $script_dir = dirname(__FILE__);
my $test_node = "$script_dir/lib/node_test.pl";
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

$config->{dbdir} .= "/update/$$";

system("mkdir", "-p", $config->{dbdir});

Munin::Common::Logger::configure(
	"output" => "screen",
	"level" => "info",
);


my $update = Munin::Master::Update->new();
ok($update->run() == 5);

# Run a second time, with an already populated database
ok($update->run() == 5);

kill('TERM', @pids);
wait();

# cleanup the update dir
system("rm", "-Rf", $config->{dbdir});

done_testing();

1;
