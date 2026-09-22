use strict;
use warnings;

use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);

use lib qw(lib);

use Munin::Master::ConfigDB;

my ($fh, $dbpath) = tempfile(CLEANUP => 1, SUFFIX => '.db');
close $fh;

my $db = Munin::Master::ConfigDB->new(dbpath => $dbpath);
ok($db, 'ConfigDB created');

# Schema creation
lives_ok { $db->ensure_schema() } 'Schema created';

# Global settings
$db->insert_global('timeout', '180');
is($db->get_global('timeout'), '180', 'Global get after insert');

$db->insert_global('timeout', '300');
is($db->get_global('timeout'), '300', 'Global overwrite');

$db->insert_global('dbdir', '/var/lib/munin');
my $all = $db->get_all_global();
is($all->{timeout}, '300', 'All globals - timeout');
is($all->{dbdir}, '/var/lib/munin', 'All globals - dbdir');

is($db->get_global('nonexistent'), undef, 'Global nonexistent returns undef');

# Hierarchy
my $hid1 = $db->ensure_hierarchy(['web', 'app1.com']);
ok(defined $hid1, 'Hierarchy created');
my $hid2 = $db->ensure_hierarchy(['web', 'app2.com']);
ok(defined $hid2, 'Hierarchy created - second host');
isnt($hid1, $hid2, 'Different hosts get different IDs');

# Same hierarchy returns same ID
my $hid3 = $db->ensure_hierarchy(['web', 'app1.com']);
is($hid3, $hid1, 'Same hierarchy returns same ID');

# Nested groups
my $hid4 = $db->ensure_hierarchy(['prod', 'webservers', 'web01.example.com']);
ok(defined $hid4, 'Nested hierarchy created');

my $found = $db->get_hierarchy_id(['web', 'app1.com']);
is($found, $hid1, 'get_hierarchy_id finds existing');

my $notfound = $db->get_hierarchy_id(['nonexistent', 'host']);
is($notfound, undef, 'get_hierarchy_id returns undef for missing');

# Host settings
$db->insert_host_setting($hid1, 'port', '4949');
is($db->get_host_setting($hid1, 'port'), '4949', 'Host setting get');

$db->insert_host_setting($hid1, 'address', '10.0.0.1');
my $settings = $db->get_all_host_settings($hid1);
is($settings->{port}, '4949', 'All host settings - port');
is($settings->{address}, '10.0.0.1', 'All host settings - address');

# Overrides
$db->insert_override(42, 'warning', '80');
is($db->get_override(42, 'warning'), '80', 'Override get');
is($db->get_override(99, 'warning'), undef, 'Override nonexistent ds');

# Glob patterns
$db->insert_glob('app*.com', 'web', 'timeout', '30');
my $matches = $db->match_glob('web', 'timeout');
is(scalar @$matches, 1, 'Glob match returns one result');
is($matches->[0][1], '30', 'Glob match value');

# Resolve value - exact match
$db->clear();
$db->ensure_schema();
$db->insert_global('timeout', '180');
$db->insert_global('dbdir', '/var/lib/munin');
my $hid = $db->ensure_hierarchy(['web', 'app1.com']);
$db->insert_host_setting($hid, 'timeout', '60');

my $val = $db->resolve_value(['web', 'app1.com'], 'timeout');
is($val, '60', 'resolve_value - exact match wins');

# Resolve value - hierarchy fallback
$val = $db->resolve_value(['web', 'app1.com'], 'dbdir');
is($val, '/var/lib/munin', 'resolve_value - falls back to global');

# Resolve value - parent hierarchy
my $hid_parent = $db->ensure_hierarchy(['web']);
$db->insert_host_setting($hid_parent, 'retries', '3');
$val = $db->resolve_value(['web', 'app1.com'], 'retries');
is($val, '3', 'resolve_value - inherits from parent group');

# Clear
$db->clear();
is($db->get_global('timeout'), undef, 'Clear removes globals');
is($db->get_hierarchy_id(['web']), undef, 'Clear removes hierarchy');

# Resolve with glob
$db->insert_glob('app*.com', 'web;app*.com', 'timeout', '30');
$val = $db->resolve_value(['web', 'app1.com'], 'timeout');
is($val, '30', 'resolve_value - glob match');

done_testing();
