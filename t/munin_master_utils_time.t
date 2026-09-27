#!/usr/bin/perl
# Tests for Munin::Master::Utils - munin_time and faketime

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Time::Local;
use Munin::Master::Utils qw(munin_time faketime);

# ============================================================================
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

print "\n";

done_testing();

1;
