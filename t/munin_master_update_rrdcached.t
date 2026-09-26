use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);

# ============================================================================
# SETUP
# ============================================================================

# Must set up config BEFORE loading UpdateWorker, as it captures $config
# at module load time via: my $config = Munin::Master::Config->instance()->{config}
use Munin::Master::Config;

my $temp_dir = tempdir("rrdcached-$$-XXXXXX", TMPDIR => 1, CLEANUP => 1);
my $config = Munin::Master::Config->instance()->{config};
$config->{dbdir}            = $temp_dir;
$config->{rrdcached_socket} = "";    # default: no rrdcached
$config->{logdir}           = $temp_dir;
$config->{fork}             = 0;

use Munin::Master::UpdateWorker;

# Mock RRDs — the real module is not needed; we only care about call patterns.
# Must be done after `use RRDs` inside UpdateWorker.pm has run.
my @rrd_update_calls;    # each entry: [$file, @args]
my $rrd_update_error;    # set to undef (ok) or a string (error)

no warnings 'redefine';
*RRDs::update = sub {
    push @rrd_update_calls, [@_];
    return;
};

*RRDs::error = sub {
    return $rrd_update_error;
};
use warnings 'redefine';

# Worker only needs dbh and node_id for _update_rrd_file
my $worker = bless { dbh => undef, node_id => 1 }, 'Munin::Master::UpdateWorker';

# Helper: reset mocks between tests
sub reset_mocks {
    @rrd_update_calls = ();
    $rrd_update_error = undef;
}

# Helper: build ds_values hash from a list of "ts:value" strings
sub make_ds_values {
    my (@entries) = @_;
    my @values;
    my @when;
    for my $e (@entries) {
        my ($ts, $val) = split /:/, $e, 2;
        push @when,   int($ts);
        push @values, $val;
    }
    return { value => \@values, when => \@when };
}

# Helper: generate N deterministic data points
sub gen_data {
    my ($n, $start_ts) = @_;
    $start_ts //= 1700000000;
    my @data;
    for my $i (0 .. $n - 1) {
        my $ts = $start_ts + $i * 300;
        my $val = ($i * 7 + 42) % 100;
        push @data, "$ts:$val";
    }
    return @data;
}

# ============================================================================
# TEST: No rrdcached — small batch (≤32)
# ============================================================================

subtest 'No rrdcached: ≤32 points → single vectorized update' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "";

    my @data = gen_data(10);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 1, "exactly 1 RRDs::update call");
    is($rrd_update_calls[0][0], "$temp_dir/test.rrd", "file path correct");
    # args: ($file, @update_data) — so @_ has file + N entries
    is(scalar @{$rrd_update_calls[0]} - 1, 10, "all 10 data points in one call");
    is($ts, 1700000000 + 9 * 300, "returns last timestamp");
};

# ============================================================================
# TEST: No rrdcached — large batch (>32)
# ============================================================================

subtest 'No rrdcached: >32 points → single vectorized update' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "";

    my @data = gen_data(50);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 1, "still 1 call even with >32 points");
    is(scalar @{$rrd_update_calls[0]} - 1, 50, "all 50 data points in one call");
    is($ts, 1700000000 + 49 * 300, "returns last timestamp");
};

# ============================================================================
# TEST: With rrdcached — small batch (≤32) → falls through to else
# ============================================================================

subtest 'With rrdcached: ≤32 points → single update (else branch)' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "/tmp/fake-rrdcached.sock";

    my @data = gen_data(20);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 1, "1 call — threshold not reached");
    is(scalar @{$rrd_update_calls[0]} - 1, 20, "all 20 points batched");
    is($ts, 1700000000 + 19 * 300, "returns last timestamp");

    delete $config->{rrdcached_socket};
};

# ============================================================================
# TEST: With rrdcached — large batch (>32) → individual updates
# ============================================================================

subtest 'With rrdcached: >32 points → individual updates' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "/tmp/fake-rrdcached.sock";

    my @data = gen_data(40);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 40, "40 individual RRDs::update calls");
    for my $i (0 .. 39) {
        is($rrd_update_calls[$i][0], "$temp_dir/test.rrd", "call $i: correct file");
        is(scalar @{$rrd_update_calls[$i]}, 2, "call $i: exactly 1 data point (file + 1)");
        like($rrd_update_calls[$i][1], qr/^\d+:\d+(\.\d+)?$/, "call $i: ts:value format");
    }
    is($ts, 1700000000 + 39 * 300, "returns last timestamp");

    delete $config->{rrdcached_socket};
};

# ============================================================================
# TEST: With rrdcached — exactly 33 points (boundary)
# ============================================================================

subtest 'With rrdcached: exactly 33 points → individual updates' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "/tmp/fake-rrdcached.sock";

    my @data = gen_data(33);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 33, "33 individual calls at boundary");
    is($ts, 1700000000 + 32 * 300, "returns last timestamp");

    delete $config->{rrdcached_socket};
};

# ============================================================================
# TEST: With rrdcached — exactly 32 points (just below boundary)
# ============================================================================

subtest 'With rrdcached: exactly 32 points → single update' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "/tmp/fake-rrdcached.sock";

    my @data = gen_data(32);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 1, "1 call — 32 is not > 32");
    is(scalar @{$rrd_update_calls[0]} - 1, 32, "all 32 points batched");

    delete $config->{rrdcached_socket};
};

# ============================================================================
# TEST: rrdcached error breaks the loop
# ============================================================================

subtest 'With rrdcached: error on 3rd update stops the loop' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "/tmp/fake-rrdcached.sock";

    my @data = gen_data(40);
    my $ds_values = make_ds_values(@data);

    # Fail on the 3rd call
    my $call_count = 0;
    no warnings 'redefine';
    *RRDs::update = sub {
        $call_count++;
        push @rrd_update_calls, [@_];
        if ($call_count == 3) {
            $rrd_update_error = "mock error on update 3";
        } else {
            $rrd_update_error = undef;
        }
        return;
    };
    use warnings 'redefine';

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 3, "stopped after 3rd call (error on 3rd)");
    like($rrd_update_calls[2][1], qr/^\d+:/, "3rd call was attempted");

    # Restore normal mock
    no warnings 'redefine';
    *RRDs::update = sub {
        push @rrd_update_calls, [@_];
        return;
    };
    *RRDs::error = sub {
        return $rrd_update_error;
    };
    use warnings 'redefine';

    delete $config->{rrdcached_socket};
};

# ============================================================================
# TEST: NO_UPDATE_RRD guard suppresses RRDs::update
# ============================================================================

subtest 'NO_UPDATE_RRD=1 suppresses all RRDs::update calls' => sub {
    reset_mocks();
    $ENV{NO_UPDATE_RRD} = 1;

    my @data = gen_data(10);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 0, "no RRDs::update calls");
    is($ts, 1700000000 + 9 * 300, "still returns correct timestamp");

    delete $ENV{NO_UPDATE_RRD};
};

subtest 'NO_UPDATE_RRD=1 with rrdcached: >32 points suppressed' => sub {
    reset_mocks();
    $ENV{NO_UPDATE_RRD} = 1;
    $config->{rrdcached_socket} = "/tmp/fake-rrdcached.sock";

    my @data = gen_data(50);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 0, "no calls even with rrdcached + >32 points");
    is($ts, 1700000000 + 49 * 300, "still returns correct timestamp");

    delete $config->{rrdcached_socket};
    delete $ENV{NO_UPDATE_RRD};
};

# ============================================================================
# TEST: Non-monotonic timestamps are filtered
# ============================================================================

subtest 'Non-monotonic timestamps are skipped' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "";

    # Timestamps: 1000, 2000, 1500 (backward), 3000
    my $ds_values = {
        value => [10, 20, 15, 30],
        when  => [1000, 2000, 1500, 3000],
    };

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, 1, "1 batched call");
    # Should have 3 entries: 1000:10, 2000:20, 3000:30 (1500 skipped)
    my @entries = @{$rrd_update_calls[0]};
    shift @entries;  # remove file
    is(scalar @entries, 3, "non-monotonic timestamp 1500 filtered out");
    like($entries[0], qr/^1000:/, "first entry correct");
    like($entries[1], qr/^2000:/, "second entry correct");
    like($entries[2], qr/^3000:/, "third entry correct (skipped 1500)");
    is($ts, 3000, "returns last valid timestamp");
};

# ============================================================================
# TEST: rrdcached_socket not writable → graceful fallback
# ============================================================================

subtest 'rrdcached_socket not writable → warn and skip rrdcached' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "/nonexistent/path/socket.sock";

    my @data = gen_data(40);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    # Should fall through to the else branch (single update)
    is(scalar @rrd_update_calls, 1, "single call — rrdcached skipped");
    is(scalar @{$rrd_update_calls[0]} - 1, 40, "all 40 points batched");

    delete $config->{rrdcached_socket};
};

subtest 'rrdcached_socket exists but not writable → warn and skip' => sub {
    reset_mocks();

    # Create a read-only file to satisfy -e but fail -w
    my $ro_socket = "$temp_dir/readonly.sock";
    open my $fh, '>', $ro_socket or die "Cannot create $ro_socket: $!";
    print $fh "dummy";
    close $fh;
    chmod 0444, $ro_socket;

    $config->{rrdcached_socket} = $ro_socket;

    my @data = gen_data(40);
    my $ds_values = make_ds_values(@data);

    my $ts = $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    # Should fall through: socket exists but not writable
    is(scalar @rrd_update_calls, 1, "single call — rrdcached socket not writable");
    is(scalar @{$rrd_update_calls[0]} - 1, 40, "all 40 points batched");

    chmod 0644, $ro_socket;  # restore for cleanup
    delete $config->{rrdcached_socket};
};

# ============================================================================
# TEST: Deterministic values — same input produces same output
# ============================================================================

subtest 'Deterministic: same input → same RRDs::update args' => sub {
    reset_mocks();
    $config->{rrdcached_socket} = "";

    my @data = gen_data(5, 1000000);
    my $ds_values = make_ds_values(@data);

    $worker->_update_rrd_file("test.rrd", "field", $ds_values);
    my @first_calls = @rrd_update_calls;

    reset_mocks();
    $worker->_update_rrd_file("test.rrd", "field", $ds_values);

    is(scalar @rrd_update_calls, scalar @first_calls, "same number of calls");
    for my $i (0 .. $#first_calls) {
        is_deeply($rrd_update_calls[$i], $first_calls[$i], "call $i identical");
    }

    delete $config->{rrdcached_socket};
};

done_testing();

1;
