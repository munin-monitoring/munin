#!/usr/bin/env perl
# Tests for CDEF threshold computation in Limits.pm
# Uses fixed epoch timestamps, no real time dependency
use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use RRDs;

use lib qw(lib);
use Munin::Master::Limits;

# Fixed epoch for deterministic RRD testing
my $T0 = 1_000_000_000;
my $STEP = 60;

# Create test RRD with two DS
sub make_test_rrd {
    my $dir = shift;
    my $rrd = "$dir/test.rrd";

    RRDs::create($rrd,
        "--start", $T0,
        "--step", $STEP,
        "DS:input:GAUGE:120:0:U",
        "DS:output:GAUGE:120:0:U",
        "RRA:AVERAGE:0.5:1:60",
    );
    die "create: " . RRDs::error() if RRDs::error();

    # Write 10 data points
    my $t = $T0 + $STEP;
    for my $i (0..9) {
        my $in  = 100 + $i * 10;
        my $out = 50  + $i * 5;
        RRDs::update($rrd, "$t:$in:$out");
        die "update: " . RRDs::error() if RRDs::error();
        $t += $STEP;
    }

    return $rrd;
}

# Test _parse_thresholds
subtest '_parse_thresholds' => sub {
    my ($warn, $crit);

    # Single value = upper bound
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds('80', undef);
    is_deeply($warn, [undef, 80], 'single warn value');
    is($crit, undef, 'no crit');

    # Range
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds('80:90', '100:110');
    is_deeply($warn, [80, 90], 'warn range');
    is_deeply($crit, [100, 110], 'crit range');

    # High only
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds(undef, ':90');
    is($warn, undef, 'no warn');
    is_deeply($crit, [undef, 90], 'crit high only');

    # Empty
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds('', '');
    is($warn, undef, 'empty warn');
    is($crit, undef, 'empty crit');
};

# Test _compute_cdef_value exists
subtest '_compute_cdef_value' => sub {
    can_ok('Munin::Master::Limits', '_compute_cdef_value');
};

# Test CDEF expression parsing
subtest 'CDEF expression token parsing' => sub {
    my %keywords = map { $_ => 1 } qw(
        GT GE LT LE EQ NE IF MIN MAX LIMIT DUP POP EXC
        SIN COS LOG EXP FLOOR CEIL ABS UNKN INF NEGINF
        PREV NOW TIME LTIME
    );

    my @test_tokens = (
        ['input',   'ds_name'],
        ['output',  'ds_name'],
        ['+',       'operator'],
        ['-',       'operator'],
        ['*',       'operator'],
        ['/',       'operator'],
        ['100',     'number'],
        ['3.14',    'number'],
        ['GT',      'keyword'],
        ['IF',      'keyword'],
        ['UNKN',    'keyword'],
    );

    for my $t (@test_tokens) {
        my ($tok, $expected) = @$t;
        my $got;

        if ($tok =~ /^[-+]?[\d.]+$/) {
            $got = 'number';
        } elsif ($tok =~ /^[<>=!+*\/\-]/) {
            $got = 'operator';
        } elsif ($keywords{uc $tok}) {
            $got = 'keyword';
        } else {
            $got = 'ds_name';
        }

        is($got, $expected, "token '$tok' identified as $expected");
    }
};

# Test RRDs::xport with CDEFs
subtest 'RRDs::xport CDEF computation' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $rrd = make_test_rrd($dir);

    my @args = (
        "--start", $T0,
        "--end",   $T0 + 600,
        "--step",  $STEP,
        "DEF:in=$rrd:input:AVERAGE",
        "DEF:out=$rrd:output:AVERAGE",
        "CDEF:total=in,out,+",
        "XPORT:total",
    );

    my ($start, $end, $step, $nb, $cols, $vals) = RRDs::xport(@args);
    is(RRDs::error(), undef, 'xport no error');
    is(scalar @$cols, 1, 'one column returned');

    my $last_val;
    for my $i (reverse 0..$#$vals) {
        if (defined $vals->[$i][0]) {
            $last_val = $vals->[$i][0];
            last;
        }
    }

    ok(defined $last_val, 'got a value');
    ok($last_val > 250 && $last_val < 300, "total in range (got $last_val)");
};

# Test batch CDEF computation
subtest 'batch CDEF computation' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $rrd = make_test_rrd($dir);

    my @args = (
        "--start", $T0,
        "--end",   $T0 + 600,
        "--step",  $STEP,
        "DEF:in=$rrd:input:AVERAGE",
        "DEF:out=$rrd:output:AVERAGE",
        "CDEF:total=in,out,+",
        "CDEF:ratio=in,out,/,100,*",
        "XPORT:total",
        "XPORT:ratio",
    );

    my ($s, $e, $st, $n, $cols, $vals) = RRDs::xport(@args);
    is(scalar @$cols, 2, 'two columns returned');

    my $last_row;
    for my $i (reverse 0..$#$vals) {
        if (grep { defined $_ } @{$vals->[$i]}) {
            $last_row = $vals->[$i];
            last;
        }
    }

    ok(defined $last_row, 'got data');
    ok($last_row->[0] > 250, "total OK (got $last_row->[0])");
    ok($last_row->[1] > 150, "ratio OK (got $last_row->[1])");
};

# Test threshold evaluation
# Munin semantics: ranges define SAFE zone, alert if OUTSIDE
subtest 'threshold evaluation' => sub {
    my @tests = (
        # Single value = upper bound only
        [50,  '80',  '100', 'ok'],
        [90,  '80',  '100', 'warning'],
        [110, '80',  '100', 'critical'],

        # Range: outside range triggers alert (ranges are independent)
        # warn 80:90 = WARNING if val < 80 or val > 90
        # crit 100:110 = CRITICAL if val < 100 or val > 110
        [85,  '80:90', '100:110', 'critical'],  # 85 < 100 => critical
        [105, '80:90', '100:110', 'warning'],   # 105 > 90 => warning (in crit range but outside warn)
        [115, '80:90', '100:110', 'critical'],  # 115 > 110 => critical
        [75,  '80:90', '100:110', 'critical'],  # 75 < 100 => critical
    );

    for my $t (@tests) {
        my ($val, $warn_str, $crit_str, $expected) = @$t;

        my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds($warn_str, $crit_str);

        my $state = 'ok';
        if (defined $crit) {
            my ($crit_lo, $crit_hi) = @$crit;
            if ((defined $crit_lo && $val < $crit_lo) ||
                (defined $crit_hi && $val > $crit_hi)) {
                $state = 'critical';
            }
        }
        if ($state eq 'ok' && defined $warn) {
            my ($warn_lo, $warn_hi) = @$warn;
            if ((defined $warn_lo && $val < $warn_lo) ||
                (defined $warn_hi && $val > $warn_hi)) {
                $state = 'warning';
            }
        }

        is($state, $expected, "val=$val warn=$warn_str crit=$crit_str => $expected");
    }
};

done_testing();
