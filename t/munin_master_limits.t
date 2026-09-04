use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;

use Munin::Master::Limits;

# Test _parse_thresholds - threshold parsing

# Range format: "low:high"
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("5:15", "10:20");
    is_deeply($crit, [10, 20], "critical range 10:20");
    is_deeply($warn, [5, 15], "warning range 5:15");
}

# Single threshold: "high"
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("80", "90");
    is_deeply($crit, [undef, 90], "critical single 90");
    is_deeply($warn, [undef, 80], "warning single 80");
}

# Open-ended range: ":high"
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds(":80", ":100");
    is_deeply($crit, [undef, 100], "critical open-end :100");
    is_deeply($warn, [undef, 80], "warning open-end :80");
}

# Open-ended range: "low:"
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("3:", "5:");
    is_deeply($crit, [5, undef], "critical open-start 5:");
    is_deeply($warn, [3, undef], "warning open-start 3:");
}

# Negative values
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("-5:5", "-10:10");
    is_deeply($crit, [-10, 10], "critical range -10:10");
    is_deeply($warn, [-5, 5], "warning range -5:5");
}

# No thresholds defined
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds(undef, undef);
    is($warn, undef, "warning undef when not set");
    is($crit, undef, "critical undef when not set");
}

# Only critical defined
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds(undef, "95");
    is($warn, undef, "warning undef when only critical set");
    is_deeply($crit, [undef, 95], "critical single 95");
}

# Float thresholds
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("0.5:1.5", "1.5:2.5");
    is_deeply($crit, ["1.5", "2.5"], "critical range 1.5:2.5");
    is_deeply($warn, ["0.5", "1.5"], "warning range 0.5:1.5");
}

done_testing();

1;
