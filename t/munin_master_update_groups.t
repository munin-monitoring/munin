#!/usr/bin/perl
# Tests for Munin::Master::Update - _db_groups_update and get_hosts
#
# Tests importing groups/hosts from config tree into SQLite

use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);
use IO::Handle;

use lib qw(lib);

# ============================================================================
# SETUP: Create a temp DB and config
# ============================================================================

# Reset config singleton
delete $INC{'lib/Munin/Master/Config.pm'};
require Munin::Master::Config;

# Create temp database
my ($fh, $dbpath) = tempfile(CLEANUP => 1, SUFFIX => '.db');
close $fh;

# Create config instance and parse test config
my $config_obj = Munin::Master::Config->instance();
my $config = $config_obj->{config};

# Set up dbdir for the test
use TestState;
$config->{dbdir} = TestState::state_dir();

# Parse a test config with groups and hosts
my $test_config = <<'EOF';
dbdir /var/lib/munin
tmpldir /etc/munin/templates
fork 1
timeout 180

[web;app1.example.com]
    address 10.0.0.1
    port 4949

[web;app2.example.com]
    address 10.0.0.2

[db;db1.example.com]
    address 10.0.1.1
    port 4950
    update 0

[prod;webservers;web01.example.com]
    address 10.0.2.1
    update_priority 1
EOF

my $io = IO::Handle->new;
open($io, '<', \$test_config) or die "Cannot open string: $!";
$config->parse_config($io);
close $io;

# Now test the import

# Load Update.pm
require Munin::Master::Update;

# Create a mock Update object (we don't need to actually run update)
my $update = bless {
    config => $config,
}, 'Munin::Master::Update';

# Override get_dbh to use our temp DB
no warnings 'redefine';
*Munin::Master::Update::get_dbh = sub {
    my ($is_read_only) = @_;
    use DBI;
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$dbpath",
        '', '',
        {
            RaiseError => 1,
            AutoCommit => 0,
            sqlite_unicode => 1,
        }
    ) or die "Cannot connect: $DBI::errstr";
    return $dbh;
};
use warnings 'redefine';

# Initialize schema
{
    my $dbh = Munin::Master::Update::get_dbh();
    $update->_db_init($dbh);
    $dbh->disconnect();
}

# Test 1: Import groups
subtest 'import groups from config' => sub {
    # Run the import
    eval { $update->_db_groups_update() };
    ok(!$@, '_db_groups_update runs without error');
    diag($@) if $@;

    # Verify with get_hosts
    my $hosts = Munin::Master::Update::get_hosts();
    ok(ref $hosts eq 'ARRAY', 'get_hosts returns arrayref');
    is(scalar @$hosts, 4, 'Found 4 hosts');

    # Check host names
    my @host_names = sort map { $_->{name} } @$hosts;
    is_deeply(\@host_names, [
        'app1.example.com',
        'app2.example.com',
        'db1.example.com',
        'web01.example.com',
    ], 'Host names are correct');
};

subtest 'host attributes imported correctly' => sub {
    my $hosts = Munin::Master::Update::get_hosts();

    # Find app1.example.com
    my ($app1) = grep { $_->isa('Munin::Master::Host') && $_->{host_name} eq 'app1.example.com' } @$hosts;
    ok($app1, 'Found app1.example.com');
    is($app1->{address}, '10.0.0.1', 'app1 address correct');
    is($app1->{port}, 4949, 'app1 port correct');
    is($app1->{group}{group_name}, 'web', 'app1 group correct');
    like($app1->get_full_path, qr/web;app1\.example\.com/, 'app1 get_full_path works');

    # Find db1.example.com (has update=0)
    my ($db1) = grep { $_->isa('Munin::Master::Host') && $_->{host_name} eq 'db1.example.com' } @$hosts;
    ok($db1, 'Found db1.example.com');
    is($db1->{address}, '10.0.1.1', 'db1 address correct');
    is($db1->{port}, 4950, 'db1 port correct');
    is($db1->{update}, 0, 'db1 update disabled');
    is($db1->{group}{group_name}, 'db', 'db1 group correct');

    # Find web01.example.com (nested group)
    my ($web01) = grep { $_->isa('Munin::Master::Host') && $_->{host_name} eq 'web01.example.com' } @$hosts;
    ok($web01, 'Found web01.example.com');
    is($web01->{address}, '10.0.2.1', 'web01 address correct');
    is($web01->{update_priority}, 1, 'web01 update_priority correct');
    like($web01->get_full_path, qr/prod;webservers;web01\.example\.com/, 'web01 get_full_path works');
};

subtest 'groups exist in grp table' => sub {
    my $dbh = Munin::Master::Update::get_dbh();

    # Count groups (excluding root)
    my ($count) = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM grp WHERE id != 0'
    );
    is($count, 4, 'Found 4 groups (web, db, prod, webservers)');

    # Check group names
    my $sth = $dbh->prepare('SELECT name FROM grp WHERE id != 0 ORDER BY name');
    $sth->execute();
    my @names;
    while (my ($name) = $sth->fetchrow_array) {
        push @names, $name;
    }
    is_deeply(\@names, ['db', 'prod', 'web', 'webservers'], 'Group names correct');

    $dbh->disconnect();
};

subtest 're-import clears old data' => sub {
    # Add a host, then re-import
    my $dbh = Munin::Master::Update::get_dbh();
    $dbh->do('DELETE FROM node');
    $dbh->do('DELETE FROM grp WHERE id != 0');
    $dbh->disconnect();

    # Re-import
    $update->_db_groups_update();

    my $hosts = Munin::Master::Update::get_hosts();
    is(scalar @$hosts, 4, 'Re-import restores all 4 hosts');
};

# Test config_override import
# First, let's add some service/field config to test with
my $test_config_with_overrides = <<'EOF';
dbdir /var/lib/munin
tmpldir /etc/munin/templates

[web;app1.example.com]
    address 10.0.0.1
    port 4949
    timeout 60

[web;app1.example.com:cpu]
    graph_title CPU Usage
    user.warning 80
    user.critical 95
    user.label User

[db;db1.example.com]
    address 10.0.1.1
    timeout 120
EOF

# Re-parse config with overrides
my $io2 = IO::Handle->new;
open($io2, '<', \$test_config_with_overrides) or die "Cannot open string: $!";
$config->parse_config($io2);
close $io2;

# Re-import groups
$update->_db_groups_update();

subtest 'config overrides imported' => sub {
    # Import config
    eval { $update->_db_import_config() };
    ok(!$@, '_db_import_config runs without error');
    diag($@) if $@;

    # Check host-level override
    my $val = Munin::Master::Update::get_override('app1.example.com', '', '', 'timeout');
    is($val, '60', 'Host-level timeout override found');

    # Check service-level override
    $val = Munin::Master::Update::get_override('app1.example.com', 'cpu', '', 'graph_title');
    is($val, 'CPU Usage', 'Service-level graph_title override found');

    # Check field-level override
    $val = Munin::Master::Update::get_override('app1.example.com', 'cpu', 'user', 'warning');
    is($val, '80', 'Field-level warning override found');

    $val = Munin::Master::Update::get_override('app1.example.com', 'cpu', 'user', 'critical');
    is($val, '95', 'Field-level critical override found');

    $val = Munin::Master::Update::get_override('app1.example.com', 'cpu', 'user', 'label');
    is($val, 'User', 'Field-level label override found');

    # Check db1 timeout
    $val = Munin::Master::Update::get_override('db1.example.com', '', '', 'timeout');
    is($val, '120', 'db1 timeout override found');

    # Check nonexistent returns undef
    $val = Munin::Master::Update::get_override('app1.example.com', 'cpu', 'user', 'nonexistent');
    is($val, undef, 'Nonexistent override returns undef');
};

done_testing();
