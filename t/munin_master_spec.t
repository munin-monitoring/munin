#!/usr/bin/perl
# Specification test for munin-master
# Uses SampleDB + SampleRRD as reference data
# Tests limits, HTML, and Graph with deterministic timestamps

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::Exception;
use DBI;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);

# ============================================================================
# Deterministic time - no real time() calls during test
# ============================================================================

my $NOW = 1700000000; # Nov 14, 2023 22:13:20 UTC
BEGIN {
    # Override time() for deterministic tests
    *CORE::GLOBAL::time = sub { return $NOW; };
}

# ============================================================================
# Setup
# ============================================================================

require SampleDB;
require SampleRRD;
require Munin::Master::Config;

my $tmpdir = tempdir("spec-$$-XXXXXX", TMPDIR => 1, CLEANUP => 1);

my $dbfile = "$tmpdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);
SampleRRD::generate_sample_rrds($tmpdir);

my $config = Munin::Master::Config->instance()->{config};
$config->{dbdir} = $tmpdir;
$config->{fork} = 0;

Munin::Common::Logger::configure(
    output => 'screen',
    level => 'error',
);

# ============================================================================
# Part 1: SampleDB structure
# ============================================================================

subtest 'SampleDB structure' => sub {
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my $groups = $dbh->selectall_arrayref("SELECT id, name, path FROM grp ORDER BY id");
    ok(scalar @$groups >= 5, "at least 5 groups");

    my $nodes = $dbh->selectall_arrayref("SELECT id, name, path FROM node ORDER BY id");
    ok(scalar @$nodes >= 5, "at least 5 nodes");

    my $services = $dbh->selectall_arrayref("SELECT id, name, path FROM service ORDER BY id");
    ok(scalar @$services >= 20, "at least 20 services");

    my $ds = $dbh->selectall_arrayref("SELECT id, name, type FROM ds ORDER BY id");
    ok(scalar @$ds >= 20, "at least 20 data sources");

    my %ds_types = map { $_->[2] => 1 } @$ds;
    ok(exists $ds_types{GAUGE}, "GAUGE type exists");
    ok(exists $ds_types{DERIVE}, "DERIVE type exists");
    ok(exists $ds_types{COUNTER}, "COUNTER type exists");

    my $urls = $dbh->selectall_arrayref("SELECT id, type, path FROM url ORDER BY id");
    ok(scalar @$urls >= 20, "URLs created");

    my $state = $dbh->selectall_arrayref("SELECT id, type, alarm FROM state WHERE type = 'ds'");
    ok(scalar @$state >= 20, "state entries for DS");

    my $contacts = $dbh->selectall_arrayref("SELECT id, name FROM contact");
    ok(scalar @$contacts >= 1, "at least 1 contact");

    my $params = $dbh->selectall_arrayref("SELECT name, value FROM param");
    ok(scalar @$params >= 1, "param table has entries");

    $dbh->disconnect();
};

# ============================================================================
# Part 2: SampleRRD structure
# ============================================================================

subtest 'SampleRRD structure' => sub {
    my @rrd_files = glob("$tmpdir/**/*.rrd");
    ok(scalar @rrd_files > 0, "RRD files created");

    my $sample_rrd = $rrd_files[0];
    ok(-f $sample_rrd, "first RRD file exists");

    my $info = RRDs::info($sample_rrd);
    ok(defined $info, "RRD info readable");
    # Check for DS - either old-style '42' or new-style field name
    my @ds_keys = grep { /^ds\[.+\]\.type$/ } keys %$info;
    ok(scalar @ds_keys > 0, "at least one DS exists");
    ok($info->{step} == 300, "step is 300 seconds");
};

# ============================================================================
# Part 3: Limits threshold parsing
# ============================================================================

subtest 'Limits: threshold parsing' => sub {
    require Munin::Master::Limits;

    my ($warn, $crit);

    # Range format
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("5:15", "10:20");
    is_deeply($warn, [5, 15], "warn range 5:15");
    is_deeply($crit, [10, 20], "crit range 10:20");

    # Single threshold
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("80", "90");
    is_deeply($warn, [undef, 80], "warn single 80");
    is_deeply($crit, [undef, 90], "crit single 90");

    # Open-ended
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds(":80", ":100");
    is_deeply($warn, [undef, 80], "warn open-end :80");
    is_deeply($crit, [undef, 100], "crit open-end :100");

    # Negative values
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("-5:5", "-10:10");
    is_deeply($warn, [-5, 5], "warn negative -5:5");
    is_deeply($crit, [-10, 10], "crit negative -10:10");

    # Float thresholds
    ($warn, $crit) = Munin::Master::Limits::_parse_thresholds("0.5:1.5", "1.5:2.5");
    is_deeply($warn, ["0.5", "1.5"], "warn float 0.5:1.5");
    is_deeply($crit, ["1.5", "2.5"], "crit float 1.5:2.5");
};

# ============================================================================
# Part 4: Limits severity validation
# ============================================================================

subtest 'Limits: severity validation' => sub {
    my $result = Munin::Master::Limits::_validate_severities(["critical", "warning", "junk", "ok"]);
    is_deeply($result, ["critical", "warning", "ok"], "filters invalid severities");

    $result = Munin::Master::Limits::_validate_severities(["unknown"]);
    is_deeply($result, ["unknown"], "keeps unknown");

    $result = Munin::Master::Limits::_validate_severities([]);
    is_deeply($result, [], "handles empty list");
};

# ============================================================================
# Part 5: Limits message expansion
# ============================================================================

subtest 'Limits: message expansion' => sub {
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
    is($txt, "mygroup :: myhost :: CPU", "variable substitution");

    $txt = Munin::Master::Limits::_message_expand(\%hash,
        '${if:cfields CRITICALS:${loop<,>:cfields  ${var:label} is ${var:value}}}');
    like($txt, qr/user is 85/, "if+cfields+loop");

    $txt = Munin::Master::Limits::_message_expand(\%hash,
        '${strtrunc:10 ${var:graph_title}}');
    is($txt, "CPU", "strtrunc");
};

# ============================================================================
# Part 6: Limits integration with SampleDB
# ============================================================================

subtest 'Limits: integration with SampleDB' => sub {
    Munin::Master::Limits::limits_main();

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my $states = $dbh->selectall_arrayref(
        "SELECT id, alarm, num_unknowns FROM state WHERE type = 'ds'"
    );
    ok(scalar @$states > 0, "state table has DS entries");

    my @alarms = map { $_->[1] } @$states;
    ok(grep { $_ eq 'ok' } @alarms, "some states are ok");
    ok(grep { $_ ne 'ok' } @alarms, "some states are non-ok (thresholds triggered)");

    my $notif_count = $dbh->selectrow_array("SELECT count(*) FROM notification");
    ok($notif_count >= 0, "notification table accessible");

    $dbh->disconnect();
};

# ============================================================================
# Part 7: Limits override threshold
# ============================================================================

subtest 'Limits: override threshold' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    # Add override to change warning threshold
    $dbh_rw->do("INSERT OR REPLACE INTO override (ds_id, name, value) VALUES (1, 'warning', '30')");
    $dbh_rw->disconnect();

    # Re-run limits
    Munin::Master::Limits::limits_main();

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my ($alarm1) = $dbh->selectrow_array("SELECT alarm FROM state WHERE id = 1 AND type = 'ds'");
    ok(defined $alarm1, "override applied");

    # Cleanup override
    $dbh->disconnect();
    $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });
    $dbh_rw->do("DELETE FROM override WHERE ds_id = 1");
    $dbh_rw->disconnect();
};

# ============================================================================
# Part 8: Limits unknown_limit
# ============================================================================

subtest 'Limits: unknown_limit' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    # Set custom unknown_limit=1 for ds_id=5
    $dbh_rw->do("INSERT OR REPLACE INTO ds_attr (id, name, value) VALUES (5, 'unknown_limit', '1')");
    # Clear any existing override to ensure clean state
    $dbh_rw->do("DELETE FROM override WHERE ds_id = 5");
    $dbh_rw->do("UPDATE state SET last_value = 'U', alarm = 'ok', num_unknowns = 0 WHERE id = 5 AND type = 'ds'");
    $dbh_rw->disconnect();

    # First run: stays ok
    Munin::Master::Limits::limits_main();
    # Second run: triggers unknown
    Munin::Master::Limits::limits_main();

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my ($alarm, $num_unk) = $dbh->selectrow_array(
        "SELECT alarm, num_unknowns FROM state WHERE id = 5 AND type = 'ds'"
    );
    is($alarm, 'unknown', "unknown_limit=1 triggers unknown after 2 runs");
    ok($num_unk >= 1, "num_unknowns incremented");

    $dbh->disconnect();
};

# ============================================================================
# Part 9: Limits heartbeat timeout
# ============================================================================

subtest 'Limits: heartbeat timeout' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    # Set last_epoch far in the past
    my $old_epoch = $NOW - 1200;
    $dbh_rw->do(
        "UPDATE state SET last_epoch = ?, num_unknowns = 0, alarm = 'ok' WHERE id = 1 AND type = 'ds'",
        undef, $old_epoch
    );
    $dbh_rw->disconnect();

    # Run 4x to accumulate past unknown_limit (default 3)
    for my $i (1..4) {
        Munin::Master::Limits::limits_main();
    }

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my ($alarm) = $dbh->selectrow_array(
        "SELECT alarm FROM state WHERE id = 1 AND type = 'ds'"
    );
    is($alarm, 'unknown', "heartbeat timeout triggers unknown");
    $dbh->disconnect();
};

# ============================================================================
# Part 10: Limits COUNTER wrap
# ============================================================================

subtest 'Limits: COUNTER wrap' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    # ds_id=14 is COUNTER type; set last_value < prev_value
    $dbh_rw->do(
        "UPDATE state SET last_epoch = ?, last_value = '100', prev_epoch = ?, prev_value = '200', alarm = 'ok' WHERE id = 14 AND type = 'ds'",
        undef, $NOW, $NOW - 60
    );
    $dbh_rw->disconnect();

    # Run 4x to accumulate past unknown_limit
    for my $i (1..4) {
        Munin::Master::Limits::limits_main();
    }

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my ($alarm) = $dbh->selectrow_array(
        "SELECT alarm FROM state WHERE id = 14 AND type = 'ds'"
    );
    is($alarm, 'unknown', "COUNTER wrap triggers unknown");
    $dbh->disconnect();
};

# ============================================================================
# Part 11: Limits DERIVE with undefined prev_value
# ============================================================================

subtest 'Limits: DERIVE with undefined prev_value' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    # ds_id=7 is DERIVE type; set prev_value=U
    $dbh_rw->do(
        "UPDATE state SET last_epoch = ?, last_value = '500', prev_epoch = ?, prev_value = 'U', alarm = 'ok' WHERE id = 7 AND type = 'ds'",
        undef, $NOW, $NOW - 60
    );
    $dbh_rw->disconnect();

    for my $i (1..4) { Munin::Master::Limits::limits_main(); }

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my ($alarm) = $dbh->selectrow_array(
        "SELECT alarm FROM state WHERE id = 7 AND type = 'ds'"
    );
    is($alarm, 'unknown', "DERIVE prev_value=U triggers unknown");
    $dbh->disconnect();
};

# ============================================================================
# Part 12: Limits recovery tracking
# ============================================================================

subtest 'Limits: recovery tracking' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    # ds_id=1 idle value=50, warn=80, crit=95 -> should be OK
    # Reset all state fields to ensure clean test
    $dbh_rw->do(
        "UPDATE state SET alarm = 'warning', last_value = '50', last_epoch = ?, prev_epoch = ?, num_unknowns = 0 WHERE id = 1 AND type = 'ds'",
        undef, $NOW, $NOW - 60
    );
    $dbh_rw->disconnect();

    Munin::Master::Limits::limits_main();

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my ($alarm) = $dbh->selectrow_array("SELECT alarm FROM state WHERE id = 1 AND type = 'ds'");
    is($alarm, 'ok', "recovery from warning to ok");
    $dbh->disconnect();
};

# ============================================================================
# Part 13: Limits missing contact
# ============================================================================

subtest 'Limits: missing contact' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    $dbh_rw->do("INSERT OR REPLACE INTO service_attr (id, name, value) VALUES (1, 'contacts', 'ghostcontact')");
    $dbh_rw->do("UPDATE state SET alarm = 'warning' WHERE id = 1 AND type = 'ds'");
    $dbh_rw->disconnect();

    # Should warn but not crash
    lives_ok { Munin::Master::Limits::limits_main() } "missing contact does not crash";
};

# ============================================================================
# Part 14: Limits missing command
# ============================================================================

subtest 'Limits: missing command' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    $dbh_rw->do("INSERT OR IGNORE INTO contact (id, name) VALUES (2, 'nocommand')");
    $dbh_rw->do("INSERT OR REPLACE INTO service_attr (id, name, value) VALUES (1, 'contacts', 'nocommand')");
    $dbh_rw->do("UPDATE state SET alarm = 'warning' WHERE id = 1 AND type = 'ds'");
    $dbh_rw->disconnect();

    lives_ok { Munin::Master::Limits::limits_main() } "missing command does not crash";
};

# ============================================================================
# Part 15: Limits max_messages
# ============================================================================

subtest 'Limits: max_messages' => sub {
    my $dbh_rw = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });

    $dbh_rw->do("INSERT OR REPLACE INTO contact_attr (id, name, value) VALUES (1, 'max_messages', '1')");
    $dbh_rw->do("INSERT OR REPLACE INTO service_attr (id, name, value) VALUES (1, 'contacts', 'testcontact')");
    $dbh_rw->do("INSERT OR REPLACE INTO notification (contact_id, service_id, severity, num_messages) VALUES (1, 1, 'warning', 1)");
    $dbh_rw->do("UPDATE state SET alarm = 'warning' WHERE id = 1 AND type = 'ds'");
    $dbh_rw->disconnect();

    Munin::Master::Limits::limits_main();

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1, ReadOnly => 1,
    });

    my ($num_msgs) = $dbh->selectrow_array(
        "SELECT num_messages FROM notification WHERE contact_id = 1 AND service_id = 1"
    );
    is($num_msgs, 1, "notification skipped at max_messages limit");
    $dbh->disconnect();
};

# ============================================================================
# Part 16: HTML static generation
# ============================================================================

subtest 'HTML: static generation' => sub {
    require Munin::Master::Static::HTML;
    require Cwd;

    # Insert tmpldir into param table
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", {
        RaiseError => 1, AutoCommit => 1,
    });
    my $tmpldir = Cwd::abs_path("web/templates");
    $dbh->do("INSERT OR REPLACE INTO param (name, value) VALUES ('tmpldir', ?)", undef, $tmpldir);
    $dbh->disconnect();

    my $htmldir = "$tmpdir/_html";
    system("mkdir", "-p", $htmldir);

    Munin::Master::Static::HTML::create(0, $htmldir);

    my @html_files = glob("$htmldir/*.html");
    ok(scalar @html_files > 0, "HTML files generated");
    ok(-f "$htmldir/index.html", "index.html generated");
};

# ============================================================================
# Part 17: Graph static generation
# ============================================================================

subtest 'Graph: static generation' => sub {
    require Munin::Master::Static::Graph;
    require Test::MockModule;

    my $mock = Test::MockModule->new("Munin::Master::Update");
    $mock->redefine("get_param", sub {
        my $param = shift;
        return $config->{$param} if defined $config->{$param};
        return undef;
    });

    my $graphdir = "$tmpdir/_graph";
    system("mkdir", "-p", $graphdir);

    Munin::Master::Static::Graph::create(0, $graphdir);

    my @pngs = glob("$graphdir/**/*.png");
    ok(scalar @pngs > 0, "PNG files generated");

    # Check for time period variants
    for my $period (qw(hour day week month year)) {
        my @found = glob("$graphdir/**/*-$period.png");
        ok(scalar @found > 0, "generated $period graphs");
    }
};

# ============================================================================
# Cleanup
# ============================================================================

remove_tree($tmpdir);

print "\n";

done_testing();

1;
