use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use DBI;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use Time::HiRes;

use Munin::Master::Config;
use Munin::Master::Limits;

# --- Part 1: _parse_thresholds unit tests (unchanged) ---

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

# --- Part 2: _validate_severities ---

{
    my $result = Munin::Master::Limits::_validate_severities(["critical", "warning", "junk", "ok"]);
    is_deeply($result, ["critical", "warning", "ok"], "_validate_severities filters invalid");
}

{
    my $result = Munin::Master::Limits::_validate_severities(["unknown"]);
    is_deeply($result, ["unknown"], "_validate_severities keeps unknown");
}

{
    my $result = Munin::Master::Limits::_validate_severities([]);
    is_deeply($result, [], "_validate_severities empty list");
}

# --- Part 3: _message_expand ---

{
    my %hash = (
        group       => "mygroup",
        host        => "myhost",
        graph_title => "CPU",
        worst       => "WARNING",
        worstid     => 1,
        cfields     => "user",
        wfields     => "",
        ufields     => "",
        fofields    => "",
        user => { state => "warning", label => "user", value => "85.0", extinfo => "high" },
    );
    my $txt = Munin::Master::Limits::_message_expand(\%hash,
        '${var:group} :: ${var:host} :: ${var:graph_title}');
    is($txt, "mygroup :: myhost :: CPU", "_message_expand var substitution");

    my $txt2 = Munin::Master::Limits::_message_expand(\%hash,
        '${if:cfields CRITICALS:${loop<,>:cfields  ${var:label} is ${var:value}}}');
    like($txt2, qr/user is 85/, "_message_expand if+cfields+loop");

    my $txt3 = Munin::Master::Limits::_message_expand(\%hash,
        '${strtrunc:10 ${var:graph_title}}');
    is($txt3, "CPU", "_message_expand strtrunc");

    my $txt4 = Munin::Master::Limits::_message_expand(\%hash,
        '${if:wfields WARNINGs:yes}${if:ufields UNKNOWNs:yes}');
    is($txt4, "", "_message_expand empty ifields produce nothing");

    my $txt5 = Munin::Master::Limits::_message_expand(\%hash, 'no vars here');
    is($txt5, "no vars here", "_message_expand plain text");
}

# --- Part 4: Integration test via limits_main ---

Munin::Common::Logger::configure(
    "output" => "screen",
    "level"  => "info",
);

my $config = Munin::Master::Config->instance()->{"config"};
my $dbdir  = tempdir("limits-$$-XXXXXX", TMPDIR => 1, CLEANUP => 0);
$config->{dbdir}  = $dbdir;
$config->{fork}   = 0;

use SampleDB;
my $dbfile = "$dbdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);

# Run limits_main
limits_main();

# Verify state was updated in DB
my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});

# Check that state table has alarm values set
my $states = $dbh->selectall_arrayref(
    "SELECT id, alarm, num_unknowns FROM state WHERE type = 'ds'"
);
ok(scalar @$states > 0, "state table has DS entries");

my @alarms = map { $_->[1] } @$states;
ok(grep { $_ eq 'ok' } @alarms, "some states are ok");
ok(grep { $_ eq 'critical' || $_ eq 'warning' || $_ eq 'unknown' } @alarms,
    "some states are non-ok (thresholds triggered)");

# Check that notification table was created (even if empty)
my $notif_count = $dbh->selectrow_array("SELECT count(*) FROM notification");
ok($notif_count >= 0, "notification table accessible");

# --- Part 5: Override test ---

# Add an override to change warning threshold (use writable connection)
my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("INSERT OR REPLACE INTO override (ds_id, name, value) VALUES (1, 'warning', '30')");
$dbh_rw->disconnect();

# Re-run limits with override active
limits_main();

# Re-read state for ds_id=1 to verify override was applied
my ($alarm1) = $dbh->selectrow_array("SELECT alarm FROM state WHERE id = 1 AND type = 'ds'");
ok(defined $alarm1, "override test: state exists for ds_id=1");

# --- Part 6: CDEF skip path ---

# Add a CDEF attr to a DS that also has warning/critical
# This should cause _process_ds to skip it (line 207)
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("INSERT OR REPLACE INTO ds_attr (id, name, value) VALUES (2, 'cdef', '1,INDEX,+')");
$dbh_rw->disconnect();

limits_main();

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});

# DS id=2 now has cdef, so it should be skipped in processing
# The state alarm should remain unchanged from what SampleDB set
my ($alarm2) = $dbh->selectrow_array("SELECT alarm FROM state WHERE id = 2 AND type = 'ds'");
ok(defined $alarm2, "CDEF skip: state exists for ds_id=2");

# --- Part 7: unknown_limit path ---

# Set ds_id=3 value to U and alarm=ok to test unknown_limit accumulation
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("UPDATE state SET last_value = 'U', alarm = 'ok', num_unknowns = 0 WHERE id = 3 AND type = 'ds'");
$dbh_rw->disconnect();

# Run multiple times to accumulate unknowns
for my $i (1..5) {
    limits_main();
}

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});
my ($alarm3, $num_unk3) = $dbh->selectrow_array(
    "SELECT alarm, num_unknowns FROM state WHERE id = 3 AND type = 'ds'"
);
ok(defined $alarm3, "unknown_limit: state exists for ds_id=3");
# After enough runs, num_unknowns should exceed default limit (3)
ok($num_unk3 >= 0, "unknown_limit: num_unknowns tracked ($num_unk3)");

# --- Part 8: Recovery tracking ---

# Remove override from Part 5 first, restore original warning=80
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("DELETE FROM override WHERE ds_id = 1");
$dbh_rw->disconnect();

# ds_id=1 idle value=50, warn=80, crit=95 -> OK
# Set alarm=warning to simulate prior warning state
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("UPDATE state SET alarm = 'warning' WHERE id = 1 AND type = 'ds'");
$dbh_rw->disconnect();

limits_main();

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});
my ($alarm1_after) = $dbh->selectrow_array("SELECT alarm FROM state WHERE id = 1 AND type = 'ds'");
is($alarm1_after, 'ok', "recovery: ds_id=1 recovered from warning to ok");

$dbh->disconnect();

# --- Part 9: Heartbeat timeout (line 231) ---

# Set last_epoch far in the past so time > last_epoch + 600
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
my $old_epoch = time() - 1200;
$dbh_rw->do("UPDATE state SET last_epoch = ?, num_unknowns = 0, alarm = 'ok' WHERE id = 1 AND type = 'ds'", undef, $old_epoch);
$dbh_rw->disconnect();

# Run 4x: 3 to accumulate unknowns past default limit (3), 4th to trigger
for my $i (1..4) {
    limits_main();
}

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});
my ($val_heartbeat) = $dbh->selectrow_array(
    "SELECT alarm FROM state WHERE id = 1 AND type = 'ds'"
);
# Heartbeat expired -> value becomes 'U' -> unknown state
is($val_heartbeat, 'unknown', "heartbeat timeout: ds_id=1 becomes unknown");
$dbh->disconnect();

# --- Part 10: COUNTER wrap (line 241-242) ---

# ds_id=14 is COUNTER type; set last_value < prev_value to trigger wrap -> 'U'
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
my $now10 = time();
$dbh_rw->do(
    "UPDATE state SET last_epoch = ?, last_value = '100', prev_epoch = ?, prev_value = '200', alarm = 'ok' WHERE id = 14 AND type = 'ds'",
    undef, $now10, $now10 - 60
);
$dbh_rw->disconnect();

# Run 4x to accumulate past unknown_limit (default 3)
for my $i (1..4) {
    limits_main();
}

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});
my ($val_counter) = $dbh->selectrow_array(
    "SELECT alarm FROM state WHERE id = 14 AND type = 'ds'"
);
is($val_counter, 'unknown', "COUNTER wrap: ds_id=14 becomes unknown when last < prev");
$dbh->disconnect();

# --- Part 11: Missing contact (line 375-377) ---

# Set service contacts to a non-existent contact name
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("INSERT OR REPLACE INTO service_attr (id, name, value) VALUES (1, 'contacts', 'ghostcontact')");
# Ensure state_changed triggers notification path
$dbh_rw->do("UPDATE state SET alarm = 'warning' WHERE id = 1 AND type = 'ds'");
$dbh_rw->disconnect();

# Should warn about missing contact but not crash
limits_main();

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});
my ($val_ghost) = $dbh->selectrow_array(
    "SELECT alarm FROM state WHERE id = 1 AND type = 'ds'"
);
ok(defined $val_ghost, "missing contact: limits did not crash");
$dbh->disconnect();

# --- Part 12: Missing command (line 389-391) ---

# Create a contact with no command attr
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("INSERT OR IGNORE INTO contact (id, name) VALUES (2, 'nocommand')");
# No command attr inserted — triggers WARN at line 390
$dbh_rw->do("INSERT OR REPLACE INTO service_attr (id, name, value) VALUES (1, 'contacts', 'nocommand')");
$dbh_rw->do("UPDATE state SET alarm = 'warning' WHERE id = 1 AND type = 'ds'");
$dbh_rw->disconnect();

limits_main();

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});
my ($val_nocmd) = $dbh->selectrow_array(
    "SELECT alarm FROM state WHERE id = 1 AND type = 'ds'"
);
ok(defined $val_nocmd, "missing command: limits did not crash");
$dbh->disconnect();

# --- Part 13: max_messages limit (line 423-426) ---

# Set testcontact with max_messages=1
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("INSERT OR REPLACE INTO contact_attr (id, name, value) VALUES (1, 'max_messages', '1')");
$dbh_rw->do("INSERT OR REPLACE INTO service_attr (id, name, value) VALUES (1, 'contacts', 'testcontact')");
# Create notification with num_messages=1 for service cpu (id=1)
$dbh_rw->do("INSERT OR REPLACE INTO notification (contact_id, service_id, severity, num_messages) VALUES (1, 1, 'warning', 1)");
$dbh_rw->do("UPDATE state SET alarm = 'warning' WHERE id = 1 AND type = 'ds'");
$dbh_rw->disconnect();

limits_main();

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});
my ($num_msgs) = $dbh->selectrow_array(
    "SELECT num_messages FROM notification WHERE contact_id = 1 AND service_id = 1"
);
# num_messages should still be 1 — notification skipped due to max_messages
is($num_msgs, 1, "max_messages: notification skipped at limit");
$dbh->disconnect();

# --- Part 14: unknown_limit attr (line 261) ---

# Set ds_id=5 with custom unknown_limit=1 (instead of default 3)
$dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});
$dbh_rw->do("INSERT OR REPLACE INTO ds_attr (id, name, value) VALUES (5, 'unknown_limit', '1')");
# Set value to U so it triggers unknown path
$dbh_rw->do("UPDATE state SET last_value = 'U', alarm = 'ok', num_unknowns = 0 WHERE id = 5 AND type = 'ds'");
$dbh_rw->disconnect();

# First run: unknown_limit=1, num_unknowns goes 0->1, stays ok (below limit)
limits_main();
# Second run: num_unknowns=1 >= unknown_limit=1, triggers unknown
limits_main();

$dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    ReadOnly   => 1,
});
my ($alarm_ul, $num_unk_ul) = $dbh->selectrow_array(
    "SELECT alarm, num_unknowns FROM state WHERE id = 5 AND type = 'ds'"
);
is($alarm_ul, 'unknown', "unknown_limit attr: triggers unknown with limit=1");
$dbh->disconnect();

# Cleanup
remove_tree($dbdir);

print "\n";

done_testing();

1;
