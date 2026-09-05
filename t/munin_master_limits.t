use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use Test::Differences;
use Test::Exception;
use DBI;
use File::Temp qw(tempdir);

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

# Malformed thresholds - should not crash
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("not_a_number", "also_bad");
    ok(1, "malformed thresholds do not crash");
}

# Mixed valid/invalid
{
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("80", "not_a_number");
    is_deeply($warn, [undef, 80], "valid warning with invalid critical");
    ok(1, "mixed valid/invalid thresholds do not crash");
}

# Test override table behavior - config file overrides plugin defaults
{
    my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", {
        RaiseError => 1,
        AutoCommit => 1,
    });

    # Create test schema
    $dbh->do("CREATE TABLE grp (id INTEGER PRIMARY KEY, p_id INTEGER, name VARCHAR, path VARCHAR)");
    $dbh->do("CREATE TABLE node (id INTEGER PRIMARY KEY, grp_id INTEGER, name VARCHAR, path VARCHAR)");
    $dbh->do("CREATE TABLE service (id INTEGER PRIMARY KEY, node_id INTEGER, name VARCHAR, path VARCHAR)");
    $dbh->do("CREATE TABLE ds (id INTEGER PRIMARY KEY, service_id INTEGER, name VARCHAR, type VARCHAR)");
    $dbh->do("CREATE TABLE ds_attr (id INTEGER, name VARCHAR, value VARCHAR)");
    $dbh->do("CREATE TABLE override (ds_id INTEGER, name VARCHAR, value VARCHAR)");
    $dbh->do("CREATE TABLE state (id INTEGER, type VARCHAR, last_epoch INTEGER, last_value VARCHAR, prev_epoch INTEGER, prev_value VARCHAR, alarm VARCHAR, num_unknowns INTEGER)");

    # Insert test data
    $dbh->do("INSERT INTO grp (id, name, path) VALUES (1, 'testgroup', 'testgroup')");
    $dbh->do("INSERT INTO node (id, grp_id, name, path) VALUES (1, 1, 'testhost', 'testgroup/testhost')");
    $dbh->do("INSERT INTO service (id, node_id, name, path) VALUES (1, 1, 'cpu', 'testgroup/testhost/cpu')");
    $dbh->do("INSERT INTO ds (id, service_id, name, type) VALUES (1, 1, 'idle', 'GAUGE')");

    # Plugin default: warning=80, critical=90
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (1, 'warning', '80')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (1, 'critical', '90')");

    # Step 1: Read plugin defaults
    my $sth_attr = $dbh->prepare('SELECT name, value FROM ds_attr WHERE id = ?');
    $sth_attr->execute(1);
    my %attrs;
    while (my ($k, $v) = $sth_attr->fetchrow_array) {
        $attrs{$k} = $v;
    }
    is($attrs{warning}, '80', "plugin default warning=80");
    is($attrs{critical}, '90', "plugin default critical=90");

    # Step 2: Read overrides - none yet
    my $sth_ov = $dbh->prepare('SELECT name, value FROM override WHERE ds_id = ?');
    $sth_ov->execute(1);
    while (my ($k, $v) = $sth_ov->fetchrow_array) {
        $attrs{$k} = $v;
    }
    is($attrs{warning}, '80', "no override: warning stays 80");
    is($attrs{critical}, '90', "no override: critical stays 90");

    # Step 3: Add config override for warning only
    $dbh->do("INSERT INTO override (ds_id, name, value) VALUES (1, 'warning', '75')");

    # Step 4: Re-read - override wins
    %attrs = ();
    $sth_attr->execute(1);
    while (my ($k, $v) = $sth_attr->fetchrow_array) {
        $attrs{$k} = $v;
    }
    $sth_ov->execute(1);
    while (my ($k, $v) = $sth_ov->fetchrow_array) {
        $attrs{$k} = $v;
    }
    is($attrs{warning}, '75', "override wins: warning=75");
    is($attrs{critical}, '90', "no override: critical stays 90");

    # Step 5: Override critical too
    $dbh->do("INSERT INTO override (ds_id, name, value) VALUES (1, 'critical', '95')");

    %attrs = ();
    $sth_attr->execute(1);
    while (my ($k, $v) = $sth_attr->fetchrow_array) {
        $attrs{$k} = $v;
    }
    $sth_ov->execute(1);
    while (my ($k, $v) = $sth_ov->fetchrow_array) {
        $attrs{$k} = $v;
    }
    is($attrs{warning}, '75', "override wins: warning=75");
    is($attrs{critical}, '95', "override wins: critical=95");

    # Step 6: Parse the overridden thresholds
    my ($warn, $crit) = Munin::Master::Limits::_parse_thresholds($attrs{warning}, $attrs{critical});
    is_deeply($warn, [undef, 75], "parsed override warning");
    is_deeply($crit, [undef, 95], "parsed override critical");

    # Test override precedence: multiple overrides for same ds_id
    $dbh->do("INSERT INTO override (ds_id, name, value) VALUES (1, 'warning', '70')");
    %attrs = ();
    $sth_attr->execute(1);
    while (my ($k, $v) = $sth_attr->fetchrow_array) {
        $attrs{$k} = $v;
    }
    $sth_ov->execute(1);
    while (my ($k, $v) = $sth_ov->fetchrow_array) {
        $attrs{$k} = $v;
    }
    # Last insert wins in our query pattern
    is($attrs{warning}, '70', "second override wins: warning=70");

    $dbh->disconnect();
}

print "\n";

done_testing();

1;
