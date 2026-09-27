#!/usr/bin/perl
# Tests for Munin::Master::Utils - munin_time and faketime

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Time::Local;
use Munin::Master::Utils qw(munin_time faketime faketime_delta munin_duration_to_sec);

# ============================================================================

# ============================================================================
# TESTS: munin_duration_to_sec
# ============================================================================

subtest 'munin_duration_to_sec' => sub {
    is(munin_duration_to_sec('1s'), 1, '1s');
    is(munin_duration_to_sec('30s'), 30, '30s');
    is(munin_duration_to_sec('1m'), 60, '1m');
    is(munin_duration_to_sec('30m'), 1800, '30m');
    is(munin_duration_to_sec('1h'), 3600, '1h');
    is(munin_duration_to_sec('12h'), 43200, '12h');
    is(munin_duration_to_sec('1d'), 86400, '1d');
    is(munin_duration_to_sec('7d'), 604800, '7d');
    is(munin_duration_to_sec('1w'), 604800, '1w');
    is(munin_duration_to_sec('2w'), 1209600, '2w');
    is(munin_duration_to_sec('invalid'), 0, 'invalid returns 0');
};
# TESTS: munin_time returns real time by default
# ============================================================================

subtest 'munin_time returns real time' => sub {
    my $before = time();
    my $got = munin_time();
    my $after = time();
    ok($got >= $before && $got <= $after, "returns real time");
};

# ============================================================================
# TESTS: faketime with absolute epoch
# ============================================================================

subtest 'faketime with epoch' => sub {
    faketime(1704067200);  # 2024-01-01 00:00:00 UTC
    is(munin_time(), 1704067200, "returns frozen epoch");
    faketime(undef);
};

# ============================================================================
# TESTS: faketime with relative time
# ============================================================================

subtest 'faketime with relative time' => sub {
    my $base = time();

    faketime('+1h');
    my $got = munin_time();
    ok(abs($got - ($base + 3600)) < 2, "+1h is approximately correct");

    faketime('-1d');
    $got = munin_time();
    ok(abs($got - ($base - 86400)) < 2, "-1d is approximately correct");

    faketime('+30m');
    $got = munin_time();
    ok(abs($got - ($base + 1800)) < 2, "+30m is approximately correct");

    faketime(undef);
};

# ============================================================================
# TESTS: faketime with ISO date
# ============================================================================

subtest 'faketime with ISO date' => sub {
    faketime('2024-06-15 12:00:00');
    my $got = munin_time();
    my $expected = timelocal(0, 0, 12, 15, 5, 2024);  # June = month 5
    is($got, $expected, "ISO date parsed correctly");
    faketime(undef);
};

# ============================================================================
# TESTS: faketime clears with undef
# ============================================================================

subtest 'faketime clears' => sub {
    faketime(1704067200);
    is(munin_time(), 1704067200, "time is frozen");

    faketime(undef);
    my $before = time();
    my $got = munin_time();
    my $after = time();
    ok($got >= $before && $got <= $after, "time is real again");
};

# ============================================================================
# TESTS: time units
# ============================================================================

subtest 'faketime units' => sub {
    my $base = time();

    faketime('+1s');
    is(munin_time(), $base + 1, "+1s");

    faketime('+1m');
    is(munin_time(), $base + 60, "+1m");

    faketime('+1h');
    is(munin_time(), $base + 3600, "+1h");

    faketime('+1d');
    is(munin_time(), $base + 86400, "+1d");

    faketime('+1w');
    is(munin_time(), $base + 604800, "+1w");

    faketime(undef);
};

# ============================================================================
# TESTS: faketime_delta
# ============================================================================

subtest 'faketime_delta' => sub {
    # Start at a fixed time
    faketime(1704067200);  # 2024-01-01 00:00:00 UTC
    is(munin_time(), 1704067200, "frozen at midnight");

    # Delta from frozen time
    faketime_delta('+1h');
    is(munin_time(), 1704067200 + 3600, "+1h from midnight");

    faketime_delta('+1h');
    is(munin_time(), 1704067200 + 7200, "+2h from midnight");

    faketime_delta('-30m');
    is(munin_time(), 1704067200 + 7200 - 1800, "-30m from 2h");

    # Delta from real time when not frozen
    faketime(undef);
    my $before = time();
    faketime_delta('+5m');
    my $got = munin_time();
    ok(abs($got - ($before + 300)) < 2, "+5m from real time");

    faketime(undef);
};

print "\n";

done_testing();

1;
