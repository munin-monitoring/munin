use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Time::HiRes ();

use Munin::Master::Config;
use Munin::Master::Limits;
use Munin::Master::Update;
use SampleDB;
use TestState;

# The limits test matrix: ONE test body, every deployment shape.
#
# The same behavioral assertions run in each configuration -- serial/parallel x
# sqlite/pgsql, minus serial/pgsql (no deployment runs that shape). A
# correct implementation produces the same outcomes everywhere:
# evaluation writes state, the send ledger is stable and keyed by
# service, notifications are delivered, no children leak, FK
# constraints hold. Configurations whose backend is missing (no postgres server)
# skip cleanly; the assertions never change per configuration.
#
# The pg configurations exercise the real Update::_db_init (schema + Pg
# branches), get_dbh's Pg path, and the ON CONFLICT upserts against a
# real server -- end-to-end, not white-box probes. If a configuration fails,
# that deployment shape is broken.

# The configurations are a SELECTION, not a validity filter: all four
# FORK x DBDRIVER combinations run -- serial+pgsql is simply unlisted
# because no deployment shape runs it, so neither this test nor CI
# spends cycles on it (run it by hand: the machinery supports it).
# Under a pinned matrix configuration (MUNIN_TEST_FORK/MUNIN_TEST_DBDRIVER set
# by a CI job) only the matching configuration runs; without the env (local
# runs) all three sweep.
my @TEST_VARIANTS = (
    { name => "serial/sqlite",   fork => 0, driver => "SQLite" },
    { name => "parallel/sqlite", fork => 1, driver => "SQLite" },
    { name => "parallel/pgsql",  fork => 1, driver => "Pg" },
);

my $pinned = grep { defined $ENV{$_} }
    qw(MUNIN_TEST_FORK MUNIN_TEST_DBDRIVER);
my @run = grep {
       (!$pinned || !defined $ENV{MUNIN_TEST_FORK}
            || ($ENV{MUNIN_TEST_FORK} ? 1 : 0) == $_->{fork})
    && (!$pinned || !defined $ENV{MUNIN_TEST_DBDRIVER}
            || ($ENV{MUNIN_TEST_DBDRIVER} eq "pg" ? "Pg" : "SQLite")
                eq $_->{driver})
} @TEST_VARIANTS;
plan skip_all => "pinned matrix configuration is outside the tested selection "
    . "(run without MUNIN_TEST_FORK/MUNIN_TEST_DBDRIVER to sweep all)"
    if $pinned && !@run;

for my $test_variant (@run) {
    my $t0 = Time::HiRes::time;
    subtest $test_variant->{name} => sub {
        # The configuration dimension is environment, not code: fork mode and
        # backend are config/env, the test body is identical.
        my $config = Munin::Master::Config->instance()->{config};
        $config->{fork} = $test_variant->{fork};
        # 5 fixture hosts vs 2 slots: PFM queueing is actually
        # exercised, not just "does start() return a pid".
        $config->{max_processes} = 2;

        my $fixture;    # sqlite: state dir; pg: scratch dbname
        if ($test_variant->{driver} eq "Pg") {
            require TestPG;
            $fixture = TestPG::scratch_db();
            plan skip_all => "no usable postgres server "
                . "(the dev image ships one; see t/lib/TestPG.pm)"
                unless $fixture;
        }
        else {
            $fixture = TestState::state_dir();
        }

        # get_dbh routing: pg configurations go through the Pg driver against the
        # scratch db; sqlite configurations must not inherit any ambient env.
        local $ENV{MUNIN_DBURL};
        local $ENV{MUNIN_DBDRIVER};
        local $ENV{MUNIN_DBUSER};
        if ($test_variant->{driver} eq "Pg") {
            $ENV{MUNIN_DBURL}    = $fixture;
            $ENV{MUNIN_DBDRIVER} = "Pg";
            $ENV{MUNIN_DBUSER}   = "postgres";
        }

        if ($test_variant->{driver} eq "Pg") {
            SampleDB::generate_sample_db($fixture, "Pg");
        }
        else {
            # Direct, not TestUtils::generate_sample_db: that helper
            # routes on the ambient matrix configuration, and this test
            # arranges its own configurations -- a pinned CI env must not steer
            # the other configurations.
            SampleDB::generate_sample_db("$fixture/datafile.sqlite");
        }

        _exercise($test_variant, $fixture);
    };
    # Wall time per configuration, so regressions in a single shape are visible
    # in every run's output (the harness only reports per-file times).
    diag(sprintf("%s: %.1fs wall (fixture + 2 limits_main runs%s)",
        $test_variant->{name}, Time::HiRes::time - $t0,
        $test_variant->{driver} eq "Pg" ? " + in-image postgres startup" : ""));
}

done_testing();

# Identical assertions for every configuration.
sub _exercise {
    my ($test_variant, $fixture) = @_;

    my $config = Munin::Master::Config->instance()->{config};
    # get_dbh's sqlite fallback is "$dbdir/datafile.sqlite"; the pg
    # path reads MUNIN_DBURL and ignores dbdir entirely.
    $config->{dbdir} = $fixture unless $test_variant->{driver} eq "Pg";

    # Run 1: transitions fire, notifications flow.
    my $ran = eval { limits_main(); 1 };
    ok($ran, "limits_main completes")
        or do { diag("limits_main died: $@"); return };

    # Read-only handle through the SAME production path the master
    # uses (get_dbh(1): PRAGMA foreign_keys=ON on sqlite, native FKs
    # on pg) -- assertions never read the DB through a special door.
    #
    # Handle discipline: NO test-side handle may stay open while
    # limits_main runs in a parallel configuration. forked children inherit
    # open DBI handles, and their exit-time DESTROY disconnects them
    # for real -- the server tears down the shared connection and the
    # master's next query dies with "server closed the connection
    # unexpectedly". Same rule the production phases follow: no
    # handle may be open across a fork. So each run is bracketed by
    # open/assert/close.
    my $chk = Munin::Master::Update::get_dbh(1);

    # 1. Evaluation wrote state.
    my ($states) = $chk->selectrow_array(
        "SELECT count(*) FROM state WHERE alarm IS NOT NULL");
    ok($states > 0, "evaluation wrote state ($states rows)");

    # 2. The same fixture data yields the same alarm mix everywhere.
    my %alarm = map { $_->[0] => $_->[1] }
        @{ $chk->selectall_arrayref(
            "SELECT alarm, count(*) FROM state GROUP BY alarm") };
    ok(($alarm{ok} // 0) > 0, "some states are ok");
    ok(($alarm{warning} // 0) + ($alarm{critical} // 0)
        + ($alarm{unknown} // 0) > 0,
        "some states warn/critical/unknown");

    # 3. Ledger: delivered, and keyed by service on EVERY row -- the
    # guard for the unbounded-growth bug (a NULL service_id never
    # collides in the unique index, so rows would grow forever).
    my ($ledger) = $chk->selectrow_array(
        "SELECT count(*) FROM notification_tracking");
    my ($keyed) = $chk->selectrow_array(
        "SELECT count(*) FROM notification_tracking "
        . "WHERE service_id IS NOT NULL");
    # The ledger stores MESSAGE severity -- the worst-state words used
    # in notification text (OK/WARNING/CRITICAL/UNKNOWN), not the
    # lowercase state vocabulary of the state table.
    my ($bad_sev) = $chk->selectrow_array(
        "SELECT count(*) FROM notification_tracking WHERE severity "
        . "NOT IN ('OK','WARNING','CRITICAL','UNKNOWN')");
    ok($ledger > 0, "notifications delivered ($ledger ledger rows)");
    is($keyed, $ledger, "every ledger row is keyed by service_id");
    is($bad_sev, 0, "ledger severities are valid message states");

    # 4. No leaked children. Meaningful for the parallel configurations (PFM
    # children must be reaped); trivially true for serial -- which is
    # the point: the same expectation everywhere. (If ps is missing the
    # capture is empty and the count is 0.)
    my $ps      = qx(ps --ppid $$ -o stat= 2>/dev/null);
    my $zombies = () = ($ps =~ /\bZ/g);
    is($zombies, 0, "no zombie children after wait_all_children");

    # 5. Run 2: no state transitioned between runs. Services whose
    # default always_send (critical,warning) still matches an alarm
    # legitimately resend every run -- throttled, not suppressed -- so
    # the invariant is the one the unbounded-growth bug broke: repeat
    # sends update counters on EXISTING (contact, service) rows and
    # never spawn new ones. Also re-exercises the upsert-on-existing-
    # row path everywhere, including ON CONFLICT DO UPDATE on pg.
    my ($sum1) = $chk->selectrow_array(
        "SELECT coalesce(sum(num_messages),0) FROM notification_tracking");
    $chk->disconnect;
    my $ran2 = eval { limits_main(); 1 };
    ok($ran2, "second limits_main completes");
    my $chk2 = Munin::Master::Update::get_dbh(1);
    my ($ledger2) = $chk2->selectrow_array(
        "SELECT count(*) FROM notification_tracking");
    my ($sum2) = $chk2->selectrow_array(
        "SELECT coalesce(sum(num_messages),0) FROM notification_tracking");
    is($ledger2, $ledger, "ledger row count stable across runs");
    cmp_ok($sum2, '>=', $sum1, "repeat sends only update existing rows");

    # 6. FK enforcement is real in every configuration: a dangling url->node
    # reference must be rejected. get_dbh sets the sqlite pragma, pg
    # enforces natively -- same expectation, both drivers.
    my $rw = Munin::Master::Update::get_dbh();
    eval { $rw->do("INSERT INTO url (path, node_id) VALUES ('fk-probe', 999999)") };
    ok($@, "FK enforced: url->node dangling insert rejected");
    eval { $rw->rollback };    # AutoCommit=0 handle; abort cleanly
    $rw->disconnect;
    $chk2->disconnect;
}
