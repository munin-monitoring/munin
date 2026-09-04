use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;

use Munin::Master::Limits;

# Test get_limits_from_attrs - threshold parsing

# Range format: "low:high"
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        critical => "10:20",
        warning  => "5:15",
        unknown_limit => 5,
    });
    is_deeply($crit, [10, 20], "critical range 10:20");
    is_deeply($warn, [5, 15], "warning range 5:15");
    is($unknown_limit, 5, "unknown_limit from attrs");
}

# Single threshold: "high"
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        critical => "90",
        warning  => "80",
    });
    is_deeply($crit, [undef, 90], "critical single 90");
    is_deeply($warn, [undef, 80], "warning single 80");
    is($unknown_limit, 3, "unknown_limit defaults to 3");
}

# Open-ended range: ":high"
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        critical => ":100",
        warning  => ":80",
    });
    is_deeply($crit, [undef, 100], "critical open-end :100");
    is_deeply($warn, [undef, 80], "warning open-end :80");
}

# Open-ended range: "low:"
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        critical => "5:",
        warning  => "3:",
    });
    is_deeply($crit, [5, undef], "critical open-start 5:");
    is_deeply($warn, [3, undef], "warning open-start 3:");
}

# Negative values
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        critical => "-10:10",
        warning  => "-5:5",
    });
    is_deeply($crit, [-10, 10], "critical range -10:10");
    is_deeply($warn, [-5, 5], "warning range -5:5");
}

# No thresholds defined
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({});
    is($warn, undef, "warning undef when not set");
    is($crit, undef, "critical undef when not set");
    is($unknown_limit, 3, "unknown_limit defaults to 3");
}

# Only critical defined
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        critical => "95",
    });
    is($warn, undef, "warning undef when only critical set");
    is_deeply($crit, [undef, 95], "critical single 95");
}

# Empty attrs hash
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({});
    is($warn, undef, "warning undef for empty attrs");
    is($crit, undef, "critical undef for empty attrs");
    is($unknown_limit, 3, "unknown_limit defaults to 3 for empty attrs");
}

# Unknown limit of 0
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        unknown_limit => 0,
    });
    is($unknown_limit, 0, "unknown_limit of 0 respected");
}

# Unknown limit with spaces
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        unknown_limit => " 5 ",
    });
    is($unknown_limit, 5, "unknown_limit trimmed from spaces");
}

# Float thresholds
{
    my ($warn, $crit, $unknown_limit) = Munin::Master::Limits::get_limits_from_attrs({
        critical => "1.5:2.5",
        warning  => "0.5:1.5",
    });
    is_deeply($crit, ["1.5", "2.5"], "critical range 1.5:2.5");
    is_deeply($warn, ["0.5", "1.5"], "warning range 0.5:1.5");
}

done_testing();

1;
