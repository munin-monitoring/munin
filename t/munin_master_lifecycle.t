#!/usr/bin/perl
# End-to-end lifecycle test
# 5 deterministic update cycles with new/removed plugins
# Verifies limits at each step

use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use DBI;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);

# ============================================================================
# Deterministic time
# ============================================================================

my $NOW = 1700000000;
my $TICK = 0;
BEGIN {
    *CORE::GLOBAL::time = sub { return $NOW + $TICK; };
}

# ============================================================================
# Setup
# ============================================================================

require SampleDB;
require Munin::Master::Config;
require Munin::Master::Limits;

Munin::Common::Logger::configure(output => 'screen', level => 'error');

my $tmpdir = tempdir("lifecycle-$$-XXXXXX", TMPDIR => 1, CLEANUP => 1);
my $dbfile = "$tmpdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);

my $config = Munin::Master::Config->instance()->{config};
$config->{dbdir} = $tmpdir;
$config->{fork} = 0;

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

sub dbh_ro { DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { RaiseError => 1, AutoCommit => 1, ReadOnly => 1 }) }
sub dbh_rw { DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { RaiseError => 1, AutoCommit => 1 }) }

sub count {
    my ($table, $where) = @_;
    my $dbh = dbh_ro();
    my $sql = "SELECT count(*) FROM $table";
    $sql .= " WHERE $where" if $where;
    my ($n) = $dbh->selectrow_array($sql);
    $dbh->disconnect();
    $n;
}

sub alarm_of {
    my ($ds_id) = @_;
    my $dbh = dbh_ro();
    my ($a) = $dbh->selectrow_array("SELECT alarm FROM state WHERE id=? AND type='ds'", undef, $ds_id);
    $dbh->disconnect();
    $a;
}

sub set_value {
    my ($dbh, $ds_id, $val) = @_;
    my $epoch = $NOW + $TICK;
    $dbh->do(
        "UPDATE state SET last_epoch=?, prev_epoch=?, prev_value=last_value, last_value=?, num_unknowns=0 WHERE id=? AND type='ds'",
        undef, $epoch, $epoch - 60, $val, $ds_id
    );
}

sub insert_ds {
    my ($dbh, %o) = @_;
    $dbh->do("INSERT OR IGNORE INTO ds (id, service_id, name, type) VALUES (?, ?, ?, ?)",
        undef, $o{id}, $o{svc_id}, $o{name}, $o{type});
    $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, 'warning', ?)",
        undef, $o{id}, $o{warn}) if defined $o{warn};
    $dbh->do("INSERT OR IGNORE INTO ds_attr (id, name, value) VALUES (?, 'critical', ?)",
        undef, $o{id}, $o{crit}) if defined $o{crit};
    $dbh->do("INSERT OR IGNORE INTO state (id, type, last_epoch, last_value, prev_epoch, prev_value, alarm, num_unknowns) VALUES (?, 'ds', ?, ?, ?, ?, ?, ?)",
        undef, $o{id}, $NOW + $TICK, $o{value}, $NOW + $TICK - 60, $o{prev} // "U", $o{alarm} // "ok", 0);
}

sub insert_svc {
    my ($dbh, %o) = @_;
    $dbh->do("INSERT OR IGNORE INTO service (id, node_id, name, path, service_title) VALUES (?, ?, ?, ?, ?)",
        undef, $o{id}, $o{node_id}, $o{name}, $o{path}, $o{title});
    $dbh->do("INSERT OR IGNORE INTO service_attr (id, name, value) VALUES (?, 'contacts', 'testcontact')",
        undef, $o{id});
    $dbh->do("INSERT OR IGNORE INTO url (id, type, path) VALUES (?, 'service', ?)",
        undef, $o{id}, $o{path});
}

sub remove_svc {
    my ($dbh, $svc_id) = @_;
    my $ds_ids = $dbh->selectall_arrayref("SELECT id FROM ds WHERE service_id = ?", undef, $svc_id);
    for my $row (@$ds_ids) {
        $dbh->do("DELETE FROM state WHERE id = ? AND type = 'ds'", undef, $row->[0]);
        $dbh->do("DELETE FROM ds_attr WHERE id = ?", undef, $row->[0]);
    }
    $dbh->do("DELETE FROM ds WHERE service_id = ?", undef, $svc_id);
    $dbh->do("DELETE FROM url WHERE id = ? AND type = 'service'", undef, $svc_id);
    $dbh->do("DELETE FROM service WHERE id = ?", undef, $svc_id);
}

# ---------------------------------------------------------------------------
# Baseline
# ---------------------------------------------------------------------------

my $base_svc = count("service");
my $base_ds  = count("ds");
diag("baseline: $base_svc services, $base_ds datasources");

# SampleDB: 5 hosts × 5 services × 15 DS = 375 DS
# Key SampleDB pre-seeded states (first host = localhost):
#   ds=1  idle/GAUGE   val=50  warn=80 crit=95  alarm=ok
#   ds=2  user/GAUGE   val=85  warn=70 crit=90  alarm=ok
#   ds=8  tx/DERIVE    val=500 prev=100 warn=1000 crit=5000 alarm=ok
#   ds=11 value1/GAUGE val=U   warn=50 crit=80  alarm=ok num_unk=0
#   ds=15 value5/GAUGE val=99  warn=50 crit=80  alarm=ok

# ============================================================================
# Update 1 — baseline: verify SampleDB state triggers correct alarms
# ============================================================================

$TICK = 300;
Munin::Master::Limits::limits_main();

# GAUGE types — direct value comparison
is(alarm_of(1),  'ok',       "u1: idle=50, warn=80 → ok");
is(alarm_of(2),  'warning',  "u1: user=85, warn=70 → warning");
is(alarm_of(3),  'ok',       "u1: system=30, warn=60 → ok");
is(alarm_of(4),  'ok',       "u1: used=75000, warn=80000 → ok");
is(alarm_of(6),  'ok',       "u1: cached=1000, no thresh → ok");
is(alarm_of(12), 'warning',  "u1: value2=60, warn=50 → warning");
is(alarm_of(13), 'ok',       "u1: value3=40, warn=50 → ok");
is(alarm_of(15), 'critical', "u1: value5=99, warn=50 crit=80 → critical");

# DERIVE type — limits computes rate = (last-prev)/dt = (500-100)/60 ≈ 6.67
is(alarm_of(8),  'ok',       "u1: tx DERIVE rate=6.67, warn=1000 → ok");

# value1=U but first unknown doesn't trigger (unknown_limit=3)
is(alarm_of(11), 'ok',       "u1: value1=U, first unknown stays ok (limit=3)");

# network value1 (ds=56): scenario=3 pre-seeded as unknown
is(alarm_of(56), 'unknown',  "u1: net/value1 pre-seeded unknown → unknown");

# load idle (ds=61): scenario=4 pre-set warning, but value=50=warn=50
# threshold uses strict >, so value == warn doesn't trigger → ok
is(alarm_of(61), 'ok',       "u1: load/idle=50, warn=50 → ok (strict >)");

# ============================================================================
# Update 2 — push GAUGE values across thresholds
# ============================================================================

$TICK = 600;

{
    my $dbh = dbh_rw();
    # GAUGE: value compared directly
    set_value($dbh, 1,  "85");   # idle: 85>80 → warning
    set_value($dbh, 2,  "92");   # user: 92>90 → critical
    set_value($dbh, 3,  "95");   # system: 95>80 → critical
    set_value($dbh, 11, "30");   # value1: 30<50 → ok (recovered from U)
    set_value($dbh, 12, "99");   # value2: 99>80 → critical (was warning)
    # DERIVE: set prev_value so rate is computed correctly
    $dbh->do(
        "UPDATE state SET last_value='5500', prev_value='500' WHERE id=8 AND type='ds'"
    );
    $dbh->disconnect();
}

Munin::Master::Limits::limits_main();

is(alarm_of(1),  'warning',  "u2: idle 50→85 → warning");
is(alarm_of(2),  'critical', "u2: user 85→92 → critical");
is(alarm_of(3),  'critical', "u2: system 30→95 → critical");
is(alarm_of(11), 'ok',       "u2: value1 U→30 → ok");
is(alarm_of(12), 'critical', "u2: value2 60→99 → critical");
# tx DERIVE: rate = (5500-500)/60 = 83.33 → ok (<1000 warn)
is(alarm_of(8),  'ok',       "u2: tx DERIVE rate=83.33 → ok");

# ============================================================================
# Update 3 — add new node + plugin
# ============================================================================

$TICK = 900;

{
    my $dbh = dbh_rw();
    $dbh->do("INSERT OR IGNORE INTO grp (id, name, path) VALUES (6, 'niflheim', 'niflheim')");
    $dbh->do("INSERT OR IGNORE INTO node (id, grp_id, name, path) VALUES (6, 6, 'niflheim', 'niflheim')");

    my $svc_id = $base_svc + 1;
    insert_svc($dbh, id => $svc_id, node_id => 6, name => "dns",
               path => "niflheim/dns", title => "DNS Queries");

    # queries: warn=1000, crit=5000, value=500 → ok
    my $ds_q = $base_ds + 1;
    insert_ds($dbh, id => $ds_q, svc_id => $svc_id, name => "queries",
              type => "GAUGE", warn => "1000", crit => "5000", value => "500");

    # errors: warn=10, crit=50, value=2 → ok
    my $ds_e = $base_ds + 2;
    insert_ds($dbh, id => $ds_e, svc_id => $svc_id, name => "errors",
              type => "GAUGE", warn => "10", crit => "50", value => "2");
    $dbh->disconnect();
}

is(count("service"), $base_svc + 1, "u3: service count +1");
is(count("ds"), $base_ds + 2,       "u3: ds count +2");

Munin::Master::Limits::limits_main();

is(alarm_of($base_ds + 1), 'ok',       "u3: dns/queries=500, warn=1000 → ok");
is(alarm_of($base_ds + 2), 'ok',       "u3: dns/errors=2, warn=10 → ok");
is(alarm_of(1),  'warning',            "u3: idle still warning");
is(alarm_of(2),  'critical',           "u3: user still critical");

# ============================================================================
# Update 3b — push new plugin past thresholds
# ============================================================================

$TICK = 1100;

{
    my $dbh = dbh_rw();
    set_value($dbh, $base_ds + 1, "3500");  # 3500>1000 → warning
    set_value($dbh, $base_ds + 2, "25");    # 25>10 → warning
    $dbh->disconnect();
}

Munin::Master::Limits::limits_main();

is(alarm_of($base_ds + 1), 'warning',  "u3b: dns/queries=3500 > warn=1000 → warning");
is(alarm_of($base_ds + 2), 'warning',  "u3b: dns/errors=25 > warn=10 → warning");

# ============================================================================
# Update 3c — push errors to critical
# ============================================================================

$TICK = 1200;

{
    my $dbh = dbh_rw();
    set_value($dbh, $base_ds + 2, "55");  # 55>50 → critical
    $dbh->disconnect();
}

Munin::Master::Limits::limits_main();

is(alarm_of($base_ds + 2), 'critical', "u3c: dns/errors=55 > crit=50 → critical");

# ============================================================================
# Update 4 — remove a plugin
# ============================================================================

$TICK = 1300;

{
    my $dbh = dbh_rw();
    my ($svc_id) = $dbh->selectrow_array("SELECT id FROM service WHERE path = 'svartalfar/load'");
    ok(defined $svc_id, "u4: found svartalfar/load to remove");
    remove_svc($dbh, $svc_id);
    $dbh->disconnect();
}

is(count("service"), $base_svc, "u4: service count back to baseline");

{
    my $dbh = dbh_ro();
    my $orphaned = $dbh->selectrow_array(
        "SELECT count(*) FROM state WHERE type='ds' AND id NOT IN (SELECT id FROM ds)"
    );
    is($orphaned, 0, "u4: no orphaned state");
    $dbh->disconnect();
}

Munin::Master::Limits::limits_main();

is(alarm_of(1),  'warning',            "u4: idle still warning");
is(alarm_of(2),  'critical',           "u4: user still critical");
is(alarm_of($base_ds + 1), 'warning',  "u4: dns/queries still warning");
is(alarm_of($base_ds + 2), 'critical', "u4: dns/errors still critical");

# ============================================================================
# Update 5 — recover everything
# ============================================================================

$TICK = 1500;

{
    my $dbh = dbh_rw();
    set_value($dbh, 1,             "40");   # idle: warning→ok
    set_value($dbh, 2,             "60");   # user: critical→ok
    set_value($dbh, 3,             "50");   # system: critical→ok
    set_value($dbh, 8,             "800");  # tx: reset to reasonable rate
    set_value($dbh, $base_ds + 1,  "200");  # dns/queries: warning→ok
    set_value($dbh, $base_ds + 2,  "1");    # dns/errors: critical→ok
    $dbh->disconnect();
}

Munin::Master::Limits::limits_main();

is(alarm_of(1),  'ok', "u5: idle recovered → ok");
is(alarm_of(2),  'ok', "u5: user recovered → ok");
is(alarm_of(3),  'ok', "u5: system recovered → ok");
is(alarm_of($base_ds + 1), 'ok', "u5: dns/queries recovered → ok");
is(alarm_of($base_ds + 2), 'ok', "u5: dns/errors recovered → ok");

# ============================================================================
# Final consistency
# ============================================================================

{
    my $dbh = dbh_ro();
    my $ds_count    = $dbh->selectrow_array("SELECT count(*) FROM ds");
    my $state_count = $dbh->selectrow_array("SELECT count(*) FROM state WHERE type='ds'");
    is($state_count, $ds_count, "every ds has a state entry");

    my $svc_no_url = $dbh->selectrow_array(
        "SELECT count(*) FROM service s WHERE NOT EXISTS (SELECT 1 FROM url u WHERE u.id=s.id AND u.type='service')"
    );
    is($svc_no_url, 0, "every service has a URL");

    my $orphaned = $dbh->selectrow_array(
        "SELECT count(*) FROM state WHERE type='ds' AND id NOT IN (SELECT id FROM ds)"
    );
    is($orphaned, 0, "no orphaned state");
    $dbh->disconnect();
}

# ============================================================================
# Cleanup
# ============================================================================

remove_tree($tmpdir);

print "\n";

done_testing();

1;
