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

# Build the SampleDB fixture in $dir. Returns the sqlite db path.
# DB-only tests (limits, lifecycle, handle_request) use this -- no RRDs.
#
#   my $dbfile = TestUtils::generate_sample_db($dbdir);
sub generate_sample_db {
    my ($dir) = @_;

    require SampleDB;
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
sub dbh_ro {
    my ($dbfile) = @_;
    require DBI;
    return DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { RaiseError => 1, ReadOnly => 1 });
}

sub dbh_rw {
    my ($dbfile) = @_;
    require DBI;
    return DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { RaiseError => 1 });
}

1;
