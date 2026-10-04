use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::Differences;
use Test::Exception;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use IO::Socket::INET;
use POSIX qw(:sys_wait_h);

require_ok( 'Munin::Master::Update' );
require_ok( 'Munin::Master::Config' );

# Constants
use constant {
	NODE_START_TIMEOUT => 30,
	UPDATE_RUNS        => 5,
	DATA_DELAY         => 2,
};

# Global state for cleanup
my @child_pids;
my $temp_dir;
my $TEST_PID = $$;    # END cleanup runs only in this process

# Cleanup on any exit
END {
	# Pid-guarded: forked update workers inherit this END block
	# (finish() -> exit() runs END in the child).  Unguarded, a worker
	# kills the shared test nodes, deletes the state dir under the
	# master, and -- via $? = 0 -- clobbers its own exit code so
	# run_on_finish never sees worker failures.  Only the original
	# test process cleans up.
	return if $$ != $TEST_PID;
	if (@child_pids) {
		kill('TERM', @child_pids);
		for my $pid (@child_pids) {
			waitpid($pid, 0);
		}
	}
	if ($temp_dir && -d $temp_dir) {
		remove_tree($temp_dir);
	}
	$? = 0;
}

# Launch minimal test nodes with spoolfetch support
my $script_dir = __FILE__;
$script_dir =~ s{/[^/]+$}{};
my $test_node = "$script_dir/lib/node_test_spool.pl";

my @ports = get_free_ports(3);

for my $port (@ports) {
	my $pid = fork();
	if ($pid == 0) {
		exec("perl", $test_node, $port, "30");
		die "exec failed: $!";
	}
	push @child_pids, $pid;
}

# Wait for nodes to be ready (poll ports instead of sleep)
my $all_ready = wait_for_ports(\@ports, NODE_START_TIMEOUT);
ok($all_ready, "all test nodes are listening");

unless ($all_ready) {
	kill('TERM', @child_pids);
	die "Test nodes failed to start";
}

# Generate config with actual ports
use TestState;
use TestUtils;
$temp_dir = TestState::state_dir();

# Not setup_test_config(): generates its own conf with the ephemeral
# ports the forked test nodes actually bound -- t/config/munin.conf's
# fixed ports would collide.
my $conf_file = TestUtils::generate_test_conf($temp_dir, \@ports);

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file($conf_file);

$config->{dbdir} = $temp_dir;
$config->{fork} = TestUtils::fork_mode();

Munin::Common::Logger::configure(
	"output" => "screen",
	"level" => "info",
);

# alarm_or_die, not bare alarm: untrapped SIGALRM skips END, orphaned
# test nodes hold the TAP pipe, prove wedges (see TestUtils).
TestUtils::alarm_or_die(90);

my $update = Munin::Master::Update->new();
is($update->run(), UPDATE_RUNS, "first update run returns expected count");

# Run a second time, with an already populated database
is($update->run(), UPDATE_RUNS, "second update run returns expected count");

# Run a third time, but wait for some more data to arrive
sleep(DATA_DELAY);
is($update->run(), UPDATE_RUNS, "third update run returns expected count");

alarm(0);

print "\n";

done_testing();

1;

# --- Helper functions ---

sub get_free_ports {
	my ($count) = @_;
	my @ports;
	for (1 .. $count) {
		my $sock = IO::Socket::INET->new(
			LocalAddr => '127.0.0.1',
			LocalPort => 0,
			Proto     => 'tcp',
		);
		if ($sock) {
			push @ports, $sock->sockport();
			close($sock);
		} else {
			die "Cannot find free port: $!";
		}
	}
	return @ports;
}

sub wait_for_ports {
	my ($ports, $timeout) = @_;
	my $start = time();

	for my $port (@$ports) {
		my $ready = 0;
		while (time() - $start < $timeout) {
			my $sock = IO::Socket::INET->new(
				PeerAddr => '127.0.0.1',
				PeerPort => $port,
				Proto    => 'tcp',
				Timeout  => 1,
			);
			if ($sock) {
				close($sock);
				$ready = 1;
				last;
			}
			select(undef, undef, undef, 0.1);
		}
		return 0 unless $ready;
	}
	return 1;
}
