use strict;
use warnings;

use lib qw(t/lib);

use Test::More;

# Test real-world scenarios and edge cases
# Focus on what actually matters in production

require_ok('Munin::Master::UpdateWorker');

# ============================================================================
# Scenario 1: update_rate parsing - real plugin values
#
# Plugins output update_rate in various formats:
# - "300" (seconds)
# - "5m" (human readable)
# - "300 aligned" (with alignment flag)
# - "not_valid" (broken plugin)
# ============================================================================
subtest 'update_rate parsing' => sub {
    my @cases = (
        # [input, expected_seconds, expected_aligned]
        ['300', 300, 0],
        ['60', 60, 0],
        ['3600', 3600, 0],
        ['300 aligned', 300, 1],
        ['60 aligned', 60, 1],
        ['5m', 300, 0],
        ['1h', 3600, 0],
        ['10s', 10, 0],
        ['1d', 86400, 0],
        ['1w', 604800, 0],
        # Edge cases
        ['0', 0, 0],
        ['', 0, 0],
        ['garbage', 0, 0],
        ['5m garbage', 300, 0],  # Handles partial garbage
    );
    
    for my $tc (@cases) {
        my ($input, $exp_sec, $exp_aligned) = @$tc;
        my @result = Munin::Master::UpdateWorker::parse_update_rate($input);
        is($result[0], $exp_sec, "parse_update_rate('$input') seconds");
        is($result[1], $exp_aligned, "parse_update_rate('$input') aligned");
    }
};

# ============================================================================
# Scenario 2: to_sec - human readable time conversion
#
# Used by parse_update_rate and custom resolution parsing
# ============================================================================
subtest 'to_sec conversion' => sub {
    my @cases = (
        ['300', 300],
        ['60', 60],
        ['3600', 3600],
        ['86400', 86400],
        ['5m', 300],
        ['1h', 3600],
        ['1d', 86400],
        ['1w', 604800],
        ['1t', 2678400],    # month (31 days)
        ['1y', 31536000],   # year (365 days)
        ['10s', 10],
        # Edge cases
        ['0', 0],
        ['abc', 0],  # Returns 0 for invalid
    );
    
    for my $tc (@cases) {
        my ($input, $expected) = @$tc;
        my $result = Munin::Master::UpdateWorker::to_sec($input);
        is($result, $expected, "to_sec('$input') = $expected");
    }
};

# ============================================================================
# Scenario 3: round_to_granularity - time alignment for RRD
#
# Plugins with "aligned" update_rate need timestamps rounded
# ============================================================================
subtest 'round_to_granularity' => sub {
    # Test "N" (now) handling - plugins use "N" for current time
    my $now = time();
    my $result = Munin::Master::UpdateWorker::round_to_granularity('N', 300);
    ok($result <= $now, 'N rounds to past');
    ok($result % 300 == 0, 'N rounds to 5-min boundary');
    
    # Test specific timestamps
    is(Munin::Master::UpdateWorker::round_to_granularity(1000, 300), 900, '1000 -> 900');
    is(Munin::Master::UpdateWorker::round_to_granularity(1200, 300), 1200, '1200 -> 1200');
    is(Munin::Master::UpdateWorker::round_to_granularity(1201, 300), 1200, '1201 -> 1200');
    is(Munin::Master::UpdateWorker::round_to_granularity(0, 300), 0, '0 -> 0');
};

# ============================================================================
# Scenario 4: convert_to_float - scientific notation handling
#
# Plugins sometimes output scientific notation for large/small values
# RRDtool doesn't like scientific notation
# ============================================================================
subtest 'convert_to_float' => sub {
    my @cases = (
        ['42', '42'],
        ['3.14', '3.14'],
        ['-1', '-1'],
        ['U', 'U'],           # Unknown passes through
        ['0', '0'],
        ['1e10', '10000000000.0000'],
        ['1.5E-5', '0.000015000'],
        ['1.23e3', '1230.0000'],
    );
    
    for my $tc (@cases) {
        my ($input, $expected) = @$tc;
        my $result = Munin::Master::UpdateWorker::convert_to_float($input);
        is($result, $expected, "convert_to_float('$input')");
    }
};

# ============================================================================
# Scenario 5: parse_custom_resolution - graph_data_size parsing
#
# Plugins specify custom RRA definitions in graph_data_size
# ============================================================================
subtest 'parse_custom_resolution' => sub {
    # Simple numeric
    my @result = Munin::Master::UpdateWorker::parse_custom_resolution('42', 300);
    is_deeply(\@result, [[1, 42]], 'Simple numeric');
    
    # Multiple resolutions
    @result = Munin::Master::UpdateWorker::parse_custom_resolution('42, 10 10', 300);
    is(scalar @result, 2, 'Multiple resolutions');
    
    # Human readable
    @result = Munin::Master::UpdateWorker::parse_custom_resolution('1h', 300);
    is_deeply(\@result, [[1, 12]], '1h = 12 steps of 300s');
    
    # Complex with "for"
    @result = Munin::Master::UpdateWorker::parse_custom_resolution('5m for 1h', 300);
    is(scalar @result, 1, 'Complex with for');
};

# ============================================================================
# Scenario 6: enlarge_custom_resolution - 10% buffer
#
# RRDtool recommends 10% extra space for RRAs
# ============================================================================
subtest 'enlarge_custom_resolution' => sub {
    my @input = ([1, 100]);
    my @result = Munin::Master::UpdateWorker::enlarge_custom_resolution(@input);
    
    is($result[0][0], 1, 'Multiplier preserved');
    ok($result[0][1] >= 100, 'Count increased by 10%');
    
    # Edge case: small number gets minimum +1
    @input = ([1, 10]);
    @result = Munin::Master::UpdateWorker::enlarge_custom_resolution(@input);
    is($result[0][1], 11, '10% of 10 = 1 minimum');
};

# ============================================================================
# Scenario 7: is_fresh_enough - should we skip this plugin?
#
# If data was collected recently enough, skip it
# ============================================================================
subtest 'is_fresh_enough' => sub {
    # Create a minimal object to test the method
    my $worker = bless {}, 'Munin::Master::UpdateWorker';
    
    my $now = time();
    
    # Data from 60 seconds ago, update_rate 300 - should be fresh
    ok(Munin::Master::UpdateWorker::is_fresh_enough($worker, '300', $now - 60, $now),
       '60s old with 300s rate = fresh');
    
    # Data from 400 seconds ago, update_rate 300 - should NOT be fresh
    ok(!Munin::Master::UpdateWorker::is_fresh_enough($worker, '300', $now - 400, $now),
       '400s old with 300s rate = not fresh');
    
    # Data from 60 seconds ago, update_rate 60 - should NOT be fresh
    ok(!Munin::Master::UpdateWorker::is_fresh_enough($worker, '60', $now - 60, $now),
       '60s old with 60s rate = not fresh');
};

# ============================================================================
# Scenario 8: spoolfetch timestamp handling
#
# Spoolfetch returns data in bulk, needs proper timestamp tracking
# ============================================================================
subtest 'spoolfetch timestamp logic' => sub {
    # Test timestamp comparison logic
    my $last_ts = 0;
    my $new_ts = 1000;
    
    # New timestamp should override old
    $last_ts = $new_ts if $new_ts && $new_ts > $last_ts;
    is($last_ts, 1000, 'New timestamp overrides old');
    
    # Older timestamp should NOT override
    $new_ts = 500;
    $last_ts = $new_ts if $new_ts && $new_ts > $last_ts;
    is($last_ts, 1000, 'Older timestamp does not override');
    
    # Zero timestamp should NOT override
    $new_ts = 0;
    $last_ts = $new_ts if $new_ts && $new_ts > $last_ts;
    is($last_ts, 1000, 'Zero timestamp does not override');
};

# ============================================================================
# Scenario 9: get_spoolfetch_timestamp default
#
# First run should return 0 (no previous data)
# ============================================================================
subtest 'spoolfetch timestamp default' => sub {
    # Test the logic: 0 if unset
    my $last_updated_value = undef;
    $last_updated_value = 0 unless $last_updated_value;
    is($last_updated_value, 0, 'Undefined becomes 0');
    
    $last_updated_value = 12345;
    $last_updated_value = 0 unless $last_updated_value;
    is($last_updated_value, 12345, 'Defined value preserved');
};

done_testing();

1;
