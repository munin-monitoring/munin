use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;

use Munin::Master::Config;
use Munin::Master::Limits;
use Munin::Master::Update;
use TestState;
use TestUtils;

# limits_startup() first principles. Every variable it touches is
# lexical, so nothing can be peeked at directly -- everything is
# asserted behaviorally: config-parse side effects on the Config
# singleton, notification behavior for --force, and subprocess exit
# contracts for the paths that end in exit().

my $script = "script/munin-limits";

Munin::Common::Logger::configure(output => "screen", level => "error");

# --- CLI contract: --help and --version exit 0 with the right text ---
{
    my $out = qx($^X -Iblib/lib $script --help 2>&1);
    is($?, 0, "--help exits 0");
    like($out, qr/Usage:/, "--help prints usage");
}
{
    my $out = qx($^X -Iblib/lib $script --version 2>&1);
    is($?, 0, "--version exits 0");
    like($out, qr/munin-limits/, "--version names the binary");
}

# --- Root guard: refuses to run as root without --force-run-as-root ---
# (In the dev container the suite runs as root, so this branch is live;
# on a developer host it is skipped rather than faked.)
SKIP: {
    skip "not running as root; the guard is a no-op here", 2
        if $> != 0;
    my $out = qx($^X -Iblib/lib $script --config /dev/null 2>&1);
    isnt($?, 0, "refuses to run as root without the flag");
    like($out, qr/Aborting/, "explains the refusal");
}

# --- --config lands in the Config singleton ---
{
    my $dir = TestState::state_dir();
    my $conffile = "$dir/munin.conf";
    {
        open my $fh, '>', $conffile or die "cannot write $conffile: $!";
        print $fh "dbdir $dir\nfork 0\n";
        close $fh;
    }

    limits_startup(["--config", $conffile, "--force-run-as-root"]);

    my $config = Munin::Master::Config->instance()->{config};
    is($config->{dbdir}, $dir,
        "limits_startup parsed --config into the singleton (dbdir)");
    is($config->{fork}, 0,
        "config fork value visible to limits_main");
}

# --- --force re-sends even when no state transitioned ---
{
    my $dir = TestState::state_dir();
    my $conffile = "$dir/munin.conf";
    {
        open my $fh, '>', $conffile or die "cannot write $conffile: $!";
        print $fh "dbdir $dir\nfork 0\n";
        close $fh;
    }

    my $config = Munin::Master::Config->instance()->{config};
    $config->{dbdir} = $dir;
    $config->{fork}  = 0;

    TestUtils::generate_sample_db($dir);

    # Pin the send semantics: an empty always_send means obsess=0, so
    # steady-state runs send ONLY on transitions -- making the run-2
    # freeze deterministic instead of dependent on which fixture
    # services happen to have warning/critical alarms.
    my $rw = Munin::Master::Update::get_dbh();
    $rw->do("INSERT INTO contact_attr (id, name, value) "
        . "VALUES (1, 'always_send', '')");
    $rw->commit;
    $rw->disconnect;

    my $chk = Munin::Master::Update::get_dbh(1);
    my $send_sum = sub {
        my ($sum) = $chk->selectrow_array(
            "SELECT coalesce(sum(num_messages),0) "
            . "FROM notification_tracking");
        return $sum;
    };
    my $ledger_rows = sub {
        my ($rows) = $chk->selectrow_array(
            "SELECT count(*) FROM notification_tracking");
        return $rows;
    };

    # Run 1: the fixture's seeded alarms differ from the computed ones
    # (e.g. idle seeded 'warning', computed 'ok') -> edges -> sends.
    limits_main();
    ok($ledger_rows->() > 0, "run 1 delivered notifications");
    my $sum1 = $send_sum->();

    # Run 2: state unchanged and always_send empty -> nothing sent.
    limits_main();
    is($send_sum->(), $sum1,
        "without --force, a steady state sends nothing");

    # Run 3: --force sends despite the unchanged state. This is the
    # behavioral proof of the --force path inside limits_startup (its
    # always_send expansion is lexical and cannot be inspected).
    limits_startup(["--config", $conffile, "--force-run-as-root",
                    "--force"]);
    limits_main();
    cmp_ok($send_sum->(), '>', $sum1,
        "--force re-sends without state transitions");

    $chk->disconnect;
}

done_testing();
