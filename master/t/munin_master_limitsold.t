# -*- perl -*-
use warnings;
use strict;

use Test::More tests => 7;

use_ok('Munin::Master::LimitsOld');

# Test values
my $severities_csv = ["ok,warning,critical,unknown"];
my $severities_mix = [ "ok,Warning, CRITICAL", "unknown" ];
my $severities_bad = [ "ok", "warning", "critical", "unknown", "fluffy" ];
my $severities_dup = [ "ok", "warning", "ok", "critical", "unknown" ];

# Result value (must be sorted)
my $severities = [ "critical", "ok", "unknown", "warning" ];

is_deeply( Munin::Master::LimitsOld::validate_severities($severities),
    $severities, "validate always-send" );

is_deeply( Munin::Master::LimitsOld::validate_severities($severities_csv),
    $severities, "validate always-send (comma separated)" );

is_deeply( Munin::Master::LimitsOld::validate_severities($severities_mix),
    $severities, "validate always-send (mixed separation and case)" );

is_deeply( Munin::Master::LimitsOld::validate_severities($severities_bad),
    $severities, "validate always-send (with bad value)" );

is_deeply( Munin::Master::LimitsOld::validate_severities($severities_dup),
    $severities, "validate always-send (with duplicate value)" );

is_deeply( Munin::Master::LimitsOld::validate_severities([]),
    [], "validate always-send (with empty list)" );
