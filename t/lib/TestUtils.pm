package TestUtils;

# Shared test helpers. Consolidates byte-identical setup that was
# copy-pasted across t/*.t:
#
#   rglob                 -- recursive glob (core glob('**/*.x') does NOT
#                            recurse; '**' silently degenerates to '*')
#   setup_test_config     -- parse t/config/munin.conf, point dbdir at a
#                            fresh TestState dir, set tmpldir
#   generate_sample_db    -- build SampleDB in a dir (DB-only tests)
#   generate_sample_db_and_rrds -- build SampleDB + SampleRRD (render tests)
#   mock_update_get_param -- Munin::Master::Update::get_param mock reading
#                            from the Config singleton
#   dbh_ro / dbh_rw       -- read-only / read-write DBI handles for a
#                            test sqlite db
#   generate_test_conf    -- integration-test munin.conf with ephemeral
#                            ports for forked test nodes

use strict;
use warnings;

use File::Find qw(find);
use Test::MockModule;

# Recursive glob. Core Perl glob('**/*.x') does NOT recurse -- '**'
# behaves like '*', which only ever matches one directory level. Use this
# wherever an assertion means "at any depth".
#
#   my @pngs = TestUtils::rglob($site_dir, qr/\.png\z/);
#
# $re is matched against the full path, so anchor with \z as needed.
sub rglob {
    my ($dir, $re) = @_;
    my @found;
    return @found unless -d $dir;
    find({ wanted => sub { push @found, $File::Find::name if /$re/ }, no_chdir => 1 }, $dir);
    return @found;
}

# Standard test-config setup: parse the shared conf, allocate a TestState
# dbdir, set tmpldir. Returns ($config, $dbdir). Callers add any extra
# keys they need (staticdir, fork, ...) after.
#
#   my ($config, $dbdir) = TestUtils::setup_test_config();
sub setup_test_config {
    require Munin::Master::Config;
    require TestState;

    my $config = Munin::Master::Config->instance()->{"config"};
    $config->parse_config_from_file("t/config/munin.conf");

    my $dbdir = TestState::state_dir();
    $config->{dbdir}   = $dbdir;
    $config->{tmpldir} = "web/templates/";

    return ($config, $dbdir);
}

# --- test-matrix configuration (Makefile FORK/DBDRIVER args -> container env) ---
#
# Every FORK x DBDRIVER combination is runnable; the CI matrix selects
# the three that map to real deployment shapes. When the env is absent
# (prove run directly, outside docker) the default is the usual local
# shape: sqlite + fork.
my $PG_DBNAME;    # pg configurations: current scratch database for this process

sub fork_mode {
    return exists $ENV{MUNIN_TEST_FORK}
        ? ($ENV{MUNIN_TEST_FORK} ? 1 : 0)
        : 1;
}

sub db_driver {
    my $d = exists $ENV{MUNIN_TEST_DBDRIVER}
        ? $ENV{MUNIN_TEST_DBDRIVER}
        : "sqlite";
    return $d eq "pg" ? "Pg" : "SQLite";
}

# Route the production handle path (get_dbh reads env/config, not our
# memo) and any TestUtils helper to this process's scratch database.
sub _pg_route {
    my ($dbname) = @_;
    $PG_DBNAME = $dbname;
    $ENV{MUNIN_DBURL}    = $dbname;
    $ENV{MUNIN_DBDRIVER} = "Pg";
    $ENV{MUNIN_DBUSER}   = "postgres";
}

sub _pg_scratch {
    require TestPG;
    my $dbname = TestPG::scratch_db();
    die "TestUtils: pg configuration but no usable postgres server "
      . "(see t/lib/TestPG.pm; or run without MUNIN_TEST_DBDRIVER=pg)\n"
        unless $dbname;
    _pg_route($dbname);
    return $dbname;
}

# Build the SampleDB fixture in $dir. Returns the sqlite db path.
# DB-only tests (limits, lifecycle, handle_request) use this -- no RRDs.
#
# pg configurations: the fixture goes to a per-process scratch database -- a
# FRESH one per call, matching sqlite's fresh-file-per-call semantics
# (tests mutate state between generate calls and expect pristine
# fixtures; into a populated database SampleDB's ON CONFLICT DO NOTHING
# inserts would no-op and leave stale rows). The dbname is memoized so
# dbh_ro/dbh_rw route there; the passed $dir still hosts RRDs/confs.
#
#   my $dbfile = TestUtils::generate_sample_db($dbdir);
sub generate_sample_db {
    my ($dir) = @_;

    require SampleDB;

    if (db_driver() eq "Pg") {
        my $dbname = _pg_scratch();
        SampleDB::generate_sample_db($dbname, "Pg");
        return $dbname;
    }

    my $dbfile = "$dir/datafile.sqlite";
    SampleDB::generate_sample_db($dbfile);

    return $dbfile;
}

# Build SampleDB + SampleRRD in $dir. Graph/HTML render tests need the
# RRD files. Returns the sqlite db path.
#
#   my $dbfile = TestUtils::generate_sample_db_and_rrds($dbdir);
sub generate_sample_db_and_rrds {
    my ($dir) = @_;

    my $dbfile = generate_sample_db($dir);

    require SampleRRD;
    SampleRRD::generate_sample_rrds($dir);

    return $dbfile;
}

# Install a Munin::Master::Update::get_param mock that serves values from
# the Config singleton. Returns the Test::MockModule so the caller can
# hold it in scope (the mock is removed when the object is destroyed).
#
#   my $mock_update = TestUtils::mock_update_get_param($config);
sub mock_update_get_param {
    my ($config) = @_;

    my $mock = Test::MockModule->new("Munin::Master::Update");
    $mock->redefine("get_param", sub {
        my $param = shift;
        return $config->{$param} if defined $config->{$param};
        return undef;
    });

    return $mock;
}

# Read-only and read-write DBI handles for a test sqlite db. These
# replace the ~50 copy-pasted DBI->connect blocks in limits.t and spec.t.
#
# First-principles cruft findings (verified empirically 2026-10-02):
#   - AutoCommit => 1 is REDUNDANT: DBI's default is on, so stating it
#     changes nothing. Omitted here on purpose -- do not re-add.
#   - PrintError is MOOT alongside RaiseError => 1: RaiseError dies
#     before PrintError would warn. Never set both.
# ReadOnly opens the db read-only (DBI core attr, DBD::SQLite honors it)
# so a SELECT-only test cannot mutate the fixture by accident.
#
#   my $ro = TestUtils::dbh_ro($dbfile);
#   my $rw = TestUtils::dbh_rw($dbfile);
#
# Constraints are enforced by the storage layer on EVERY handle: a FK
# that is not switched on is decoration ("data is king"). The PRAGMA
# must run while AutoCommit is on -- sqlite silently ignores
# foreign_keys changes inside a transaction.
sub dbh_ro {
    my ($dbfile) = @_;
    require DBI;
    # pg configuration: route to the process's scratch database. The passed
    # $dbfile is sqlite-shaped (tests build it from TestState dirs
    # regardless of backend) and advisory here.
    if (db_driver() eq "Pg") {
        # On demand: tests that build their own schema through
        # dbh_rw/dbh_ro never call generate_sample_db.
        _pg_scratch() unless $PG_DBNAME;
        # No ReadOnly attr on pg: DBI warns "Setting ReadOnly in
        # AutoCommit mode has no effect". The handle is used read-only
        # by convention here, same as before.
        return DBI->connect("dbi:Pg:dbname=$PG_DBNAME", "postgres", undef,
            { RaiseError => 1 });
    }
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { RaiseError => 1, ReadOnly => 1 });
    $dbh->do("PRAGMA foreign_keys=ON");
    return $dbh;
}

sub dbh_rw {
    my ($dbfile) = @_;
    require DBI;
    if (db_driver() eq "Pg") {
        _pg_scratch() unless $PG_DBNAME;
        return DBI->connect("dbi:Pg:dbname=$PG_DBNAME", "postgres", undef,
            { RaiseError => 1 });
    }
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { RaiseError => 1 });
    $dbh->do("PRAGMA foreign_keys=ON");
    return $dbh;
}

# Generate the integration-test munin.conf with the ephemeral ports the
# forked test nodes actually bound. All four dirs (dbdir/htmldir/logdir/
# rundir) point at $dir; $ports is an arrayref of 3 ports. Returns the
# conf file path.
#
# NOT used by update_rrdcached_integration.t: that test needs separate
# html/run dirs, an rrdcached_socket line, and loop-generated group/host
# nodes -- folding it in would need an option bag that obscures more than
# it dedups.
#
#   my $conf_file = TestUtils::generate_test_conf($temp_dir, \@ports);
sub generate_test_conf {
    my ($dir, $ports) = @_;

    my $conf_file = "$dir/munin.conf";
    open my $fh, '>', $conf_file or die "Cannot write $conf_file: $!";
    print $fh "dbdir   $dir\n";
    print $fh "htmldir $dir\n";
    print $fh "logdir  $dir\n";
    print $fh "rundir  $dir\n";
    print $fh "local_address 127.0.0.1\n";
    print $fh "graph_data_size debug\n";
    # Configuration-driven: the parallel configurations exercise the forked update path
    # through the conf, not only through the config singleton.
    print $fh "fork " . fork_mode() . "\n";
    print $fh "\n";
    print $fh "[aesir;alfheim.aesir;aegir.alfheim.aesir]\n";
    print $fh "     address 127.0.0.1\n";
    print $fh "     port $ports->[0]\n";
    print $fh "\n";
    print $fh "[asynjur;asgard.asynjur;alaisiagae.asgard.asynjur]\n";
    print $fh "     address 127.0.0.1\n";
    print $fh "     port $ports->[1]\n";
    print $fh "\n";
    print $fh "[svartalfar;jotunheim.svartalfar;astrild.jotunheim.svartalfar]\n";
    print $fh "     address 127.0.0.1\n";
    print $fh "     port $ports->[2]\n";
    print $fh "\n";
    print $fh "[localhost]\n";
    print $fh "     port $ports->[0]\n";
    print $fh "\n";
    print $fh "[testing.acme.com]\n";
    print $fh "     port $ports->[1]\n";
    close $fh;

    return $conf_file;
}

1;
