package TestUtils;

# Shared test helpers. Consolidates byte-identical setup that was
# copy-pasted across t/*.t:
#
#   rglob                 -- recursive glob (core glob('**/*.x') does NOT
#                            recurse; '**' silently degenerates to '*')
#   setup_test_config     -- parse t/config/munin.conf, point dbdir at a
#                            fresh TestState dir, set tmpldir
#   generate_sample_data  -- build SampleDB (+ SampleRRD) in a dir
#   mock_update_get_param -- Munin::Master::Update::get_param mock reading
#                            from the Config singleton

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

# Build the sample fixture in $dir. Returns the sqlite db path. Set
# $with_rrds to 0 to skip SampleRRD (limits-style tests only need the DB).
#
#   my $dbfile = TestUtils::generate_sample_data($dbdir);
sub generate_sample_data {
    my ($dir, $with_rrds) = @_;
    $with_rrds = 1 unless defined $with_rrds;

    require SampleDB;
    my $dbfile = "$dir/datafile.sqlite";
    SampleDB::generate_sample_db($dbfile);

    if ($with_rrds) {
        require SampleRRD;
        SampleRRD::generate_sample_rrds($dir);
    }

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

1;
