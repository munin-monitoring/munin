use strict;
use warnings;

use Test::More;
use Test::Exception;
use File::Temp qw(tempfile tempdir);
use File::Slurp qw(write_file);

use lib qw(lib);

use Munin::Master::ConfigParser;
use Munin::Master::ConfigDB;

# Test basic string parsing
subtest 'Parse new syntax' => sub {
    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
dbdir = /var/lib/munin
logdir = /var/log/munin
timeout = 180

[web]
address = 10.0.0.1

[web;app1.com]
port = 4949

[web;app2.example.com]
port = 4950
EOF

    is($p->globals->{dbdir}, '/var/lib/munin', 'Global dbdir');
    is($p->globals->{logdir}, '/var/log/munin', 'Global logdir');
    is($p->globals->{timeout}, '180', 'Global timeout');

    is($p->sections->{web}{address}, '10.0.0.1', 'Group address');
    is($p->sections->{'web;app1.com'}{port}, '4949', 'Host port 1');
    is($p->sections->{'web;app2.example.com'}{port}, '4950', 'Host port 2');
    ok(!$p->has_errors(), 'No parse errors');
};

# Test legacy syntax
subtest 'Parse legacy syntax' => sub {
    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
dbdir /var/lib/munin
logdir /var/log/munin

[web;app1.com]
    address 127.0.0.1
    port 4949
EOF

    is($p->globals->{dbdir}, '/var/lib/munin', 'Legacy global');
    is($p->sections->{'web;app1.com'}{address}, '127.0.0.1', 'Legacy host address');
    is($p->sections->{'web;app1.com'}{port}, '4949', 'Legacy host port');
    ok(!$p->has_errors(), 'No parse errors for legacy');
};

# Test mixed syntax
subtest 'Parse mixed syntax' => sub {
    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
dbdir = /var/lib/munin
logdir /var/log/munin

[web]
address = 10.0.0.1

[web;app1.com]
    port 4949
EOF

    is($p->globals->{dbdir}, '/var/lib/munin', 'Mixed - new global');
    is($p->globals->{logdir}, '/var/log/munin', 'Mixed - legacy global');
    is($p->sections->{web}{address}, '10.0.0.1', 'Mixed - new section');
    is($p->sections->{'web;app1.com'}{port}, '4949', 'Mixed - legacy section');
    ok(!$p->has_errors(), 'No parse errors for mixed');
};

# Test comments
subtest 'Comments' => sub {
    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
# This is a comment
; This is also a comment
dbdir = /var/lib/munin
# another comment
timeout = 180
EOF

    is(scalar keys %{$p->globals}, 2, 'Two globals parsed');
    ok(!$p->has_errors(), 'No errors with comments');
};

# Test quotes
subtest 'Quoted values' => sub {
    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
label = "CPU Usage"
info = 'System load'
EOF

    is($p->globals->{label}, 'CPU Usage', 'Double quoted value');
    is($p->globals->{info}, 'System load', 'Single quoted value');
};

# Test context reset between files
subtest 'Context reset' => sub {
    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
[web]
address = 10.0.0.1
EOF

    $p->parse_string(<<'EOF');
[db]
address = 10.0.0.2
EOF

    is($p->sections->{web}{address}, '10.0.0.1', 'First file section');
    is($p->sections->{db}{address}, '10.0.0.2', 'Second file section');
    ok(!exists $p->sections->{web}{db}, 'Context reset - no leak');
};

# Test glob patterns
subtest 'Glob patterns' => sub {
    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
[web;app*.com]
timeout = 30

[*;*.example.com]
graph = no
EOF

    is(scalar @{$p->globs}, 2, 'Two globs stored');
    is($p->globs->[0][3], '30', 'Glob value');
};

# Test semicolon hierarchy
subtest 'Semicolon hierarchy' => sub {
    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
[prod;webservers;app1.example.com;cpu]
cpu.user.warning = 70
EOF

    my $key = 'prod;webservers;app1.example.com;cpu';
    is($p->sections->{$key}{'cpu.user.warning'}, '70', 'Deep hierarchy');
};

# Test file parsing
subtest 'Parse file' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $file = "$dir/test.conf";
    write_file($file, <<'EOF');
dbdir = /var/lib/munin
[web]
address = 10.0.0.1
EOF

    my $p = Munin::Master::ConfigParser->new();
    $p->parse_file($file);

    is($p->globals->{dbdir}, '/var/lib/munin', 'File parse - global');
    is($p->sections->{web}{address}, '10.0.0.1', 'File parse - section');
};

# Test import to DB
subtest 'Import to DB' => sub {
    my ($fh, $dbpath) = tempfile(CLEANUP => 1, SUFFIX => '.db');
    close $fh;

    my $db = Munin::Master::ConfigDB->new(dbpath => $dbpath);
    $db->ensure_schema();

    my $p = Munin::Master::ConfigParser->new();
    $p->parse_string(<<'EOF');
dbdir = /var/lib/munin
timeout = 180

[web]
address = 10.0.0.1

[web;app1.com]
port = 4949
EOF

    $p->import_to_db($db);

    is($db->get_global('dbdir'), '/var/lib/munin', 'Import globals');
    is($db->get_global('timeout'), '180', 'Import globals 2');

    my $hid = $db->get_hierarchy_id(['web', 'app1.com']);
    ok(defined $hid, 'Hierarchy imported');
    is($db->get_host_setting($hid, 'port'), '4949', 'Host setting imported');
};

done_testing();
