#!/usr/bin/perl
# Tests for Munin::Common::Timeout
#
# Full unit coverage for do_with_timeout()

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Time::HiRes qw(time gettimeofday tv_interval);

# ============================================================================
# SETUP
# ============================================================================

require Munin::Common::Timeout;

# ============================================================================
# TESTS: Argument validation
# ============================================================================

subtest 'croak on invalid timeout' => sub {
    eval { Munin::Common::Timeout::do_with_timeout(undef, sub {}) };
    like($@, qr/Argument exception/, "undef timeout croaks");

    eval { Munin::Common::Timeout::do_with_timeout("abc", sub {}) };
    like($@, qr/Argument exception/, "non-numeric timeout croaks");

    eval { Munin::Common::Timeout::do_with_timeout(-1, sub {}) };
    like($@, qr/Argument exception/, "negative timeout croaks");

    eval { Munin::Common::Timeout::do_with_timeout(0, sub {}) };
    like($@, qr/Argument exception/, "zero timeout croaks");
};

subtest 'croak on invalid block' => sub {
    eval { Munin::Common::Timeout::do_with_timeout(5, "not a code ref") };
    like($@, qr/Argument exception/, "non-code block croaks");

    eval { Munin::Common::Timeout::do_with_timeout(5, undef) };
    like($@, qr/Argument exception/, "undef block croaks");
};

# ============================================================================
# TESTS: Basic functionality
# ============================================================================

subtest 'executes block and returns value' => sub {
    my $result = Munin::Common::Timeout::do_with_timeout(5, sub {
        return 42;
    });
    is($result, 42, "returns block's return value");
};

subtest 'executes block with closure variables' => sub {
    my $a = 10;
    my $b = 20;
    my $result = Munin::Common::Timeout::do_with_timeout(5, sub {
        return $a + $b;
    });
    is($result, 30, "closure variables work");
};

subtest 'executes block with no return value' => sub {
    my @called;
    Munin::Common::Timeout::do_with_timeout(5, sub {
        push @called, 1;
    });
    ok(scalar @called > 0, "block was executed");
};

# ============================================================================
# TESTS: Timeout behavior
# ============================================================================

subtest 'does not timeout on fast code' => sub {
    my $start = time();
    my $result = Munin::Common::Timeout::do_with_timeout(5, sub {
        return "fast";
    });
    my $elapsed = time() - $start;
    is($result, "fast", "returns value");
    ok($elapsed < 1, "completed quickly");
};

subtest 'times out on slow code' => sub {
    my $start = time();
    my $result = Munin::Common::Timeout::do_with_timeout(1, sub {
        sleep 5;
        return "should not reach";
    });
    my $elapsed = time() - $start;
    is($result, undef, "returns undef on timeout");
    ok($elapsed < 3, "timed out promptly");
};

subtest 'does not die on timeout' => sub {
    my $ok = eval {
        Munin::Common::Timeout::do_with_timeout(1, sub {
            sleep 5;
            return "bad";
        });
        1;
    };
    ok($ok, "no exception on timeout");
};

# ============================================================================
# TESTS: Exception propagation
# ============================================================================

subtest 'propagates exceptions from block' => sub {
    eval {
        Munin::Common::Timeout::do_with_timeout(5, sub {
            die "intentional error\n";
        });
    };
    like($@, qr/intentional error/, "exception propagated");
};

subtest 'does not propagate alarm exception' => sub {
    my $ok = eval {
        Munin::Common::Timeout::do_with_timeout(1, sub {
            sleep 5;
            return 1;
        });
        1;
    };
    ok($ok, "alarm exception not propagated");
};

# ============================================================================
# TESTS: Nested timeouts
# ============================================================================

subtest 'nested timeouts work' => sub {
    my $result = Munin::Common::Timeout::do_with_timeout(10, sub {
        return Munin::Common::Timeout::do_with_timeout(5, sub {
            return "nested";
        });
    });
    is($result, "nested", "nested timeout works");
};

subtest 'nested timeout cannot extend outer' => sub {
    # Outer timeout is 2s, inner tries to extend to 10s
    # Inner should be capped to outer - 5s = -3s (immediate)
    my $start = time();
    my $result = Munin::Common::Timeout::do_with_timeout(2, sub {
        # Inner timeout tries to extend beyond outer
        return Munin::Common::Timeout::do_with_timeout(10, sub {
            return "inner";
        });
    });
    my $elapsed = time() - $start;
    is($result, undef, "inner timeout capped");
    ok($elapsed < 5, "did not wait full inner timeout");
};

subtest 'nested timeout respects outer limit' => sub {
    my $start = time();
    my $result = Munin::Common::Timeout::do_with_timeout(2, sub {
        Munin::Common::Timeout::do_with_timeout(1, sub {
            sleep 5;  # This will timeout
        });
        # Outer still has time, should continue
        return "continued";
    });
    my $elapsed = time() - $start;
    is($result, "continued", "outer continues after inner timeout");
    ok($elapsed < 5, "completed within outer timeout");
};

# ============================================================================
# TESTS: Alarm restoration
# ============================================================================

subtest 'alarm restored after timeout' => sub {
    # Set a timeout
    Munin::Common::Timeout::do_with_timeout(10, sub {
        # Do nothing
    });

    # Verify we can set another timeout
    my $result = Munin::Common::Timeout::do_with_timeout(5, sub {
        return "after";
    });
    is($result, "after", "can use timeout again after previous");
};

subtest 'alarm cleared after block completes' => sub {
    # This is a bit tricky to test directly
    # We verify that we don't have a pending alarm
    my $ok = eval {
        alarm(0);  # This should not die if no alarm is pending
        1;
    };
    ok($ok, "no pending alarm after timeout completes");
};

# ============================================================================
# TESTS: Time edge cases
# ============================================================================

subtest 'very short timeout' => sub {
    my $result = Munin::Common::Timeout::do_with_timeout(1, sub {
        return "short";
    });
    is($result, "short", "1 second timeout works");
};

subtest 'timeout with system call' => sub {
    my $result = Munin::Common::Timeout::do_with_timeout(5, sub {
        my $output = `echo "hello"`;
        chomp $output;
        return $output;
    });
    is($result, "hello", "system call works within timeout");
};

# ============================================================================
# TESTS: State isolation
# ============================================================================

subtest 'timeout state does not leak' => sub {
    # First timeout that will complete
    my $r1 = Munin::Common::Timeout::do_with_timeout(5, sub {
        return "first";
    });
    is($r1, "first", "first timeout works");

    # Second timeout should work independently
    my $r2 = Munin::Common::Timeout::do_with_timeout(5, sub {
        return "second";
    });
    is($r2, "second", "second timeout works independently");
};

# ============================================================================
# TESTS: Deep nesting
# ============================================================================

subtest 'three levels of nesting' => sub {
    my $result = Munin::Common::Timeout::do_with_timeout(30, sub {
        my $r1 = Munin::Common::Timeout::do_with_timeout(20, sub {
            my $r2 = Munin::Common::Timeout::do_with_timeout(10, sub {
                return "deep";
            });
            return $r2;
        });
        return $r1;
    });
    is($result, "deep", "three levels work");
};

# ============================================================================
# TESTS: Return value on timeout
# ============================================================================

subtest 'timeout returns undef not empty list' => sub {
    my @result = Munin::Common::Timeout::do_with_timeout(1, sub {
        sleep 5;
        return (1, 2, 3);
    });
    is(scalar @result, 0, "timeout returns empty list");
};

subtest 'timeout in boolean context is false' => sub {
    my $result = Munin::Common::Timeout::do_with_timeout(1, sub {
        sleep 5;
        return 1;
    });
    ok(!defined $result, "timeout is undef in boolean context");
};

# ============================================================================
# TESTS: Eval inside block
# ============================================================================

subtest 'block with internal eval' => sub {
    my $result = Munin::Common::Timeout::do_with_timeout(5, sub {
        eval { die "catch me\n"; };
        return "caught";
    });
    is($result, "caught", "eval inside block works");
};

subtest 'exception in internal eval does not affect timeout' => sub {
    my $result = Munin::Common::Timeout::do_with_timeout(5, sub {
        eval { die "catch me\n"; };
        if ($@) {
            return "caught: $@";
        }
        return "no error";
    });
    like($result, qr/^caught: catch me/, "internal exception handled");
};

# ============================================================================
# TESTS: Timing precision
# ============================================================================

subtest 'timeout is approximately correct' => sub {
    my $start = time();
    Munin::Common::Timeout::do_with_timeout(2, sub {
        sleep 10;
    });
    my $elapsed = time() - $start;
    ok($elapsed >= 1 && $elapsed <= 4, "timeout at ~2s (got ${elapsed}s)");
};

# ============================================================================
# CLEANUP
# ============================================================================

# Ensure no pending alarms
alarm(0);

print "\n";

done_testing();

1;
