use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use IO::Socket::INET;
use POSIX qw(:sys_wait_h);
use Fcntl qw(:mode);
use TestUtils;

# ============================================================================
# CONSTANTS
# ============================================================================

use constant {
	NODE_START_TIMEOUT => 30,
	UPDATE_TIMEOUT     => 60,
	RRDCACHED_START    => 5,
};

# Skip if rrdcached is not available
my $rrdcached_available = system("which rrdcached >/dev/null 2>&1") == 0;
unless ($rrdcached_available) {
	done_testing();
	exit(0);
}

# ============================================================================
# GLOBALS
# ============================================================================

my @child_pids;
my $temp_dir;
my $rrdcached_pid;
my $TEST_PID = $$;    # END cleanup runs only in this process

END {
	# Pid-guarded: forked update workers inherit this END block
	# (finish() -> exit() runs END in the child) and must not kill the
	# master's rrdcached/nodes or delete the shared state dir.  Only
	# the original test process cleans up.
	return if $$ != $TEST_PID;

	# Kill rrdcached first
	if ($rrdcached_pid && kill(0, $rrdcached_pid)) {
		kill 'TERM', $rrdcached_pid;
		waitpid($rrdcached_pid, 0);
	}

	# Kill test nodes
	for my $pid (@child_pids) {
		if (kill(0, $pid)) {
			kill('TERM', $pid);
			waitpid($pid, 0);
		}
	}

	if ($temp_dir && -d $temp_dir) {
		remove_tree($temp_dir);
	}
	$? = 0;
}

# ============================================================================
# HELPERS
# ============================================================================

sub get_free_port {
	my $sock = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => 0,
		Proto     => 'tcp',
	) or die "Cannot find free port: $!";
	my $port = $sock->sockport();
	close($sock);
	return $port;
}

sub wait_for_port {
	my ($port, $timeout) = @_;
	my $start = time();
	while (time() - $start < $timeout) {
		my $sock = IO::Socket::INET->new(
			PeerAddr => '127.0.0.1',
			PeerPort => $port,
			Proto    => 'tcp',
			Timeout  => 1,
		);
		if ($sock) {
			close($sock);
			return 1;
		}
		select(undef, undef, undef, 0.1);
	}
	return 0;
}

sub find_rrd_files {
	my ($dir) = @_;
	my @rrds;
	open my $fh, '-|', 'find', $dir, '-name', '*.rrd', '-type', 'f' or return();
	while (<$fh>) {
		chomp;
		push @rrds, $_;
	}
	close $fh;
	return @rrds;
}

# ============================================================================
# SETUP: Test nodes
# ============================================================================

my $script_dir = __FILE__;
$script_dir =~ s{/[^/]+$}{};
my $test_node = "$script_dir/lib/node_test.pl";

my @node_ports;
for (1 .. 3) {
	push @node_ports, get_free_port();
}

for my $port (@node_ports) {
	my $pid = fork();
	if ($pid == 0) {
		exec("perl", $test_node, $port, "10");
		die "exec failed: $!";
	}
	push @child_pids, $pid;
}

my $all_ready = 1;
for my $port (@node_ports) {
	unless (wait_for_port($port, NODE_START_TIMEOUT)) {
		$all_ready = 0;
		last;
	}
}
ok($all_ready, "test nodes are listening");

unless ($all_ready) {
	die "Test nodes failed to start";
}

# ============================================================================
# SETUP: Temp directory
# ============================================================================

use TestState;
$temp_dir = TestState::state_dir();
my $dbdir    = "$temp_dir/db";
my $sockpath = "$temp_dir/rrdcached.sock";
my $journald = "$temp_dir/journal";
my $logdir   = "$temp_dir/logs";

mkdir $dbdir;
mkdir $journald;
mkdir $logdir;

# ============================================================================
# SETUP: Start rrdcached
# ============================================================================

my $rrdcached_log = "$logdir/rrdcached.log";
open my $rrdcached_fh, '>', $rrdcached_log or die "Cannot open $rrdcached_log: $!";

$rrdcached_pid = fork();
if ($rrdcached_pid == 0) {
	open STDOUT, '>&', $rrdcached_fh;
	open STDERR, '>&', $rrdcached_fh;
	exec(
		'rrdcached',
		'-l', "unix:$sockpath",
		'-b', $dbdir,
		'-j', $journald,
		'-p', "$temp_dir/rrdcached.pid",
		'-F',                     # flush when idle
		'-g',                     # foreground (don't daemonize)
		'-V', 'LOG_DEBUG',          # verbose for debugging
	);
	die "exec rrdcached failed: $!";
}
close $rrdcached_fh;

my $rrdcached_ready = 0;
for (1 .. RRDCACHED_START * 10) {
	if (-e $sockpath && -S $sockpath) {
		$rrdcached_ready = 1;
		last;
	}
	select(undef, undef, undef, 0.1);
}
ok($rrdcached_ready, "rrdcached started and socket is ready");

# Verify socket exists and is writable
ok(-e $sockpath, "rrdcached socket file exists");
ok(-w $sockpath, "rrdcached socket file is writable");

# ============================================================================
# SETUP: Munin config
# ============================================================================

# Not setup_test_config(): generates its own conf with the ephemeral
# ports the forked test nodes actually bound -- t/config/munin.conf's
# fixed ports would collide.
my $conf_file = "$temp_dir/munin.conf";
open my $fh, '>', $conf_file or die "Cannot write $conf_file: $!";

print $fh "dbdir            $dbdir\n";
print $fh "htmldir          $temp_dir/html\n";
print $fh "logdir           $logdir\n";
print $fh "rundir           $temp_dir/run\n";
print $fh "local_address    127.0.0.1\n";
print $fh "graph_data_size  debug\n";
print $fh "fork             0\n";
print $fh "rrdcached_socket $sockpath\n";
print $fh "\n";
# Two groups, multiple nodes — forces enough data points to test batching
for my $i (0 .. 2) {
	my $group = "group-$i";
	my $host  = "host-$i";
	my $port  = $node_ports[$i];
	print $fh "[$group;$host]\n";
	print $fh "    address 127.0.0.1\n";
	print $fh "    port    $port\n";
	print $fh "\n";
}
close $fh;

# ============================================================================
# TEST: First update via rrdcached
# ============================================================================

alarm(UPDATE_TIMEOUT);

require Munin::Master::Config;
my $config = Munin::Master::Config->instance()->{config};
$config->parse_config_from_file($conf_file);
$config->{dbdir} = $dbdir;
$config->{fork}  = TestUtils::fork_mode();

require Munin::Master::Update;
Munin::Common::Logger::configure(
	"output" => "screen",
	"level"  => "info",
);

my $update = Munin::Master::Update->new();
my $run1 = $update->run();
ok($run1 > 0, "first update ran successfully (count=$run1)");

# Verify RRD files were created
my @rrd_files = find_rrd_files($dbdir);
ok(scalar @rrd_files > 0, "RRD files created (count=" . scalar @rrd_files . ")");

# Verify RRD files have content (non-zero size)
my $files_with_content = 0;
for my $rrd_file (@rrd_files) {
	$files_with_content++ if -s $rrd_file;
}
ok($files_with_content > 0, "RRD files have content ($files_with_content/" . scalar @rrd_files . ")");

# Use RRDs::last to auto-flush rrdcached and verify data is recent
use RRDs;
# The daemon legitimately holds unflushed updates -- that is what
# rrdcached is for. RRDs::last only auto-flushes through the daemon
# when RRDCACHED_ADDRESS is set (the env mechanism UpdateWorker writes
# with). At fork=1 the workers set it in their own children only, so
# the reads below must be daemon-aware themselves; at fork=0 the
# inline workers used to leak it into this process, which is the side
# effect this line makes explicit.
$ENV{RRDCACHED_ADDRESS} = $sockpath;
my $now = time();
my $recent_files = 0;
for my $rrd_file (@rrd_files) {
	my $last = RRDs::last($rrd_file);
	next if RRDs::error;
	$recent_files++ if ($now - $last) < 600;  # within 10 minutes
}
ok($recent_files > 0, "RRD files have recent data via rrdcached ($recent_files/" . scalar @rrd_files . ")");

# Record file sizes for comparison after second update
my %sizes_before;
for my $rrd_file (@rrd_files) {
	$sizes_before{$rrd_file} = -s $rrd_file;
}

# ============================================================================
# TEST: Second update — verify data persists through rrdcached
# ============================================================================

# Sleep 1 second to ensure timestamps differ
sleep 1;

$update = Munin::Master::Update->new();
my $run2 = $update->run();
ok($run2 > 0, "second update ran successfully (count=$run2)");

# Re-find RRD files (new ones may have been created)
@rrd_files = find_rrd_files($dbdir);
ok(scalar @rrd_files > 0, "RRD files still present after second update");

# Verify data was flushed through rrdcached
$now = time();
$recent_files = 0;
for my $rrd_file (@rrd_files) {
	my $last = RRDs::last($rrd_file);
	next if RRDs::error;
	$recent_files++ if ($now - $last) < 600;
}
ok($recent_files > 0, "RRD files have recent data after second update ($recent_files/" . scalar @rrd_files . ")");

# ============================================================================
# TEST: Verify no rrdcached errors in log
# ============================================================================

# Read rrdcached log and check for errors
my $rrdcached_errors = 0;
if (open my $log_fh, '<', $rrdcached_log) {
	while (<$log_fh>) {
		# rrdcached logs errors with "ERROR" or "error"
		$rrdcached_errors++ if /\berror\b/i;
	}
	close $log_fh;
}

is($rrdcached_errors, 0, "no rrdcached errors in log");

# ============================================================================
# TEST: Verify RRD data is queryable (round-trip through rrdcached)
# ============================================================================
#
# We verify the round-trip by checking RRDs::last shows recent timestamps
# after each update. A full RRDs::fetch test would require waiting for
# rrdcached to consolidate data across step boundaries (5 min for debug
# resolution), which is too slow for a unit test.
#
my $sample_file = $rrd_files[0];
my $last_update = RRDs::last($sample_file);
ok(defined $last_update && $last_update > 0, "RRD round-trip: last_update is valid ($last_update)");

alarm(0);

# ============================================================================
# CLEANUP
# ============================================================================

remove_tree($temp_dir);

print "\n";

done_testing();

1;
