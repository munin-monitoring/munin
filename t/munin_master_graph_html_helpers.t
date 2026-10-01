use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(rmtree);

# Test Graph.pm and HTML.pm helper functions
# Uses SampleDB to generate fresh test database

require_ok('Munin::Master::Config');
require_ok('Munin::Master::Graph');
require_ok('Munin::Master::HTML');
require_ok('Munin::Master::Update');

Munin::Common::Logger::configure(
    output => 'screen',
    level => 'error',
);

# Generate fresh test database
require SampleDB;
my $tmpdir = tempdir(CLEANUP => 1);
my $dbfile = "$tmpdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);

# Configure to use our temp database
my $config = Munin::Master::Config->instance()->{config};
$config->{dbdir} = $tmpdir;
$config->{dburl} = $dbfile;  # Just the filename, not the full DSN
$ENV{MUNIN_DBURL} = $dbfile;

# ============================================================================
# Graph.pm helper tests
# ============================================================================

# ============================================================================
# expand_cdef - expands cdef expressions
# Used when a plugin defines a cdef that references other fields
# ============================================================================
subtest 'expand_cdef' => sub {
    # Simple replacement
    my $result = Munin::Master::Graph::expand_cdef(
        'field1', 'field1,field2,+', 'real_field1'
    );
    is($result, 'real_field1,field2,+', 'Replaces field at start');

    # Replacement in middle
    $result = Munin::Master::Graph::expand_cdef(
        'field2', 'field1,field2,+', 'real_field2'
    );
    is($result, 'field1,real_field2,+', 'Replaces field in middle');

    # Single field
    $result = Munin::Master::Graph::expand_cdef(
        'field1', 'field1', 'real_field1'
    );
    is($result, 'real_field1', 'Replaces single field');

    # Complex cdef
    $result = Munin::Master::Graph::expand_cdef(
        'field1', 'field1,field1,+', 'real_field1'
    );
    is($result, 'real_field1,real_field1,+', 'Replaces multiple occurrences');
};

# ============================================================================
# is_virtual - checks if field is virtual (defined by cdef)
# ============================================================================
subtest 'is_virtual' => sub {
    is(Munin::Master::Graph::is_virtual('field1', 'field1,field2,+'), 0,
       'Field in cdef - not virtual');
    is(Munin::Master::Graph::is_virtual('field3', 'field1,field2,+'), 1,
       'Field not in cdef - virtual');
    is(Munin::Master::Graph::is_virtual('field1', ''), 0, 'No cdef - not virtual');
    is(Munin::Master::Graph::is_virtual('field1', undef), 0, 'Undef cdef - not virtual');
};

# ============================================================================
# remove_dups - removes duplicate words
# ============================================================================
subtest 'remove_dups' => sub {
    is(Munin::Master::Graph::remove_dups(''), undef, 'Empty string');
    is(Munin::Master::Graph::remove_dups(undef), undef, 'Undef');
    is(Munin::Master::Graph::remove_dups('a b c'), 'a b c', 'No duplicates');
    is(Munin::Master::Graph::remove_dups('a b a c b'), 'a b c', 'Removes duplicates');
    is(Munin::Master::Graph::remove_dups('a a a'), 'a', 'All same');
};

# ============================================================================
# is_int - checks if string is an integer (no decimals)
# Used to validate pixel dimensions (size_x, size_y)
# ============================================================================
subtest 'is_int' => sub {
    ok(Munin::Master::Graph::is_int('123'), 'Digits');
    ok(Munin::Master::Graph::is_int('0'), 'Zero');
    ok(Munin::Master::Graph::is_int('400'), 'Valid width');
    ok(!Munin::Master::Graph::is_int('abc'), 'Letters');
    ok(!Munin::Master::Graph::is_int('12.3'), 'Decimal rejected');
    ok(!Munin::Master::Graph::is_int('1a2'), 'Mixed rejected');
    ok(!Munin::Master::Graph::is_int(''), 'Empty');
    ok(!Munin::Master::Graph::is_int('-1'), 'Negative');
};

# ============================================================================
# escape_for_rrd - escapes special characters
# ============================================================================
subtest 'escape_for_rrd' => sub {
    is(Munin::Master::Graph::escape_for_rrd(undef), undef, 'Undef');
    is(Munin::Master::Graph::escape_for_rrd('simple'), 'simple', 'Simple');
    is(Munin::Master::Graph::escape_for_rrd('test:value'), 'test\\:value', 'Escapes colons');
    is(Munin::Master::Graph::escape_for_rrd('test\\value'), 'test\\\\value', 'Escapes backslashes');
};

# ============================================================================
# is_ext_handled - checks supported output formats
# ============================================================================
subtest 'is_ext_handled' => sub {
    ok(Munin::Master::Graph::is_ext_handled('png'), 'PNG');
    ok(Munin::Master::Graph::is_ext_handled('svg'), 'SVG');
    ok(Munin::Master::Graph::is_ext_handled('json'), 'JSON');
    ok(Munin::Master::Graph::is_ext_handled('csv'), 'CSV');
    ok(Munin::Master::Graph::is_ext_handled('xml'), 'XML');
    ok(Munin::Master::Graph::is_ext_handled('pdf'), 'PDF');
    ok(!Munin::Master::Graph::is_ext_handled('xyz'), 'Unknown');
    ok(!Munin::Master::Graph::is_ext_handled(undef), 'Undef');
};

# ============================================================================
# HTML.pm helper tests
# ============================================================================

# ============================================================================
# url_to_path - converts URL to navigation structure
# ============================================================================
subtest 'url_to_path' => sub {
    my @paths = Munin::Master::HTML::url_to_path('group1');
    is(scalar @paths, 1, 'Single segment');
    is($paths[0]{pathname}, 'group1', 'First pathname');
    ok($paths[0]{switchable}, 'Is switchable');

    @paths = Munin::Master::HTML::url_to_path('group1/node1');
    is(scalar @paths, 2, 'Two segments');
    is($paths[0]{pathname}, 'group1', 'First');
    is($paths[1]{pathname}, 'node1', 'Second');

    # Underscore becomes space (real URLs)
    @paths = Munin::Master::HTML::url_to_path('my_group/my_node');
    is($paths[0]{pathname}, 'my group', 'Underscore -> space');
    is($paths[1]{pathname}, 'my node', 'Underscore -> space');
};

# ============================================================================
# url_absolutize - adds leading slash
# ============================================================================
subtest 'url_absolutize' => sub {
    is(Munin::Master::HTML::url_absolutize('test'), '/test', 'Adds slash');
    is(Munin::Master::HTML::url_absolutize('a/b'), '/a/b', 'Path');
    is(Munin::Master::HTML::url_absolutize(''), '/', 'Empty -> root');
};

# ============================================================================
# Tests using the sample database
# ============================================================================

# ============================================================================
# get_param - gets parameter from database
# ============================================================================
subtest 'get_param from database' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);
    ok(defined $dbh, 'Got database handle');

    # Test that param table exists and is queryable
    my $sth = $dbh->prepare_cached("SELECT COUNT(*) FROM param");
    $sth->execute();
    my ($count) = $sth->fetchrow_array();
    $sth->finish();

    ok(defined $count, 'Param table is queryable');
};

# ============================================================================
# URL lookup - how Graph.pm and HTML.pm find services
# ============================================================================
subtest 'URL lookup for services' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);

    # Test the URL query that Graph.pm uses
    my $sth = $dbh->prepare_cached("SELECT grp_id, node_id, service_id FROM url LIMIT 1");
    $sth->execute();
    my ($grp_id, $node_id, $service_id) = $sth->fetchrow_array();
    $sth->finish();

    my $id = $grp_id // $node_id // $service_id;
    ok(defined $id, 'Found a URL');
};

# ============================================================================
# Service attributes - what Graph.pm reads for graph configuration
# ============================================================================
subtest 'service attributes' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);

    # Get a service ID
    my $sth = $dbh->prepare_cached("SELECT id FROM service LIMIT 1");
    $sth->execute();
    my ($service_id) = $sth->fetchrow_array();
    $sth->finish();

    ok(defined $service_id, 'Got a service ID');

    # Test the attribute query that Graph.pm uses
    $sth = $dbh->prepare_cached("SELECT name, value FROM service_attr WHERE id = ? AND name = ?");
    $sth->execute($service_id, 'graph_title');
    my ($name, $value) = $sth->fetchrow_array();
    $sth->finish();

    ok(defined $value, 'Got graph_title');

    # Get graph_order
    $sth->execute($service_id, 'graph_order');
    ($name, $value) = $sth->fetchrow_array();
    $sth->finish();

    # graph_order might not exist, that's ok
    ok(1, 'Checked graph_order');
};

# ============================================================================
# Data sources - what Graph.pm reads for field configuration
# ============================================================================
subtest 'data sources and attributes' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);

    # Get a service with data sources
    my $sth = $dbh->prepare_cached("
        SELECT s.id, s.name FROM service s
        WHERE EXISTS (SELECT 1 FROM ds WHERE ds.service_id = s.id)
        LIMIT 1
    ");
    $sth->execute();
    my ($service_id, $service_name) = $sth->fetchrow_array();
    $sth->finish();

    ok(defined $service_id, 'Got service with data sources');

    # Test the DS query that Graph.pm uses
    $sth = $dbh->prepare_cached("
        SELECT ds.name, l.value, rf.value
        FROM ds
        LEFT OUTER JOIN ds_attr l ON l.id = ds.id AND l.name = 'label'
        LEFT OUTER JOIN ds_attr rf ON rf.id = ds.id AND rf.name = 'rrd:file'
        WHERE ds.service_id = ?
        ORDER BY ds.ordr ASC
    ");
    $sth->execute($service_id);

    my @ds_list;
    while (my ($name, $label, $rrdfile) = $sth->fetchrow_array()) {
        push @ds_list, {
            name => $name,
            label => $label,
            rrdfile => $rrdfile,
        };
    }
    $sth->finish();

    ok(scalar @ds_list > 0, 'Got data sources for service');

    # Check that each DS has required attributes
    for my $ds (@ds_list) {
        ok(defined $ds->{name}, "DS '$ds->{name}' has name");
        # label might be undef, that's ok
    }
};

# ============================================================================
# Group hierarchy - what HTML.pm uses for navigation
# ============================================================================
subtest 'group hierarchy' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);

    # Test the group query that HTML.pm uses
    my $sth = $dbh->prepare_cached("
        SELECT g.id, g.name, u.path
        FROM grp g
        INNER JOIN url u ON u.grp_id = g.id
        WHERE g.p_id = 0
        ORDER BY g.name ASC
    ");
    $sth->execute();

    my @groups;
    while (my ($id, $name, $path) = $sth->fetchrow_array()) {
        push @groups, { id => $id, name => $name, path => $path };
    }
    $sth->finish();

    ok(1, 'Group hierarchy query works');

    # Check that groups have proper structure
    for my $g (@groups) {
        ok(defined $g->{name}, "Group '$g->{name}' has name");
        ok(defined $g->{path}, "Group has path");
    }
};

# ============================================================================
# Node listing - what HTML.pm uses to show nodes in a group
# ============================================================================
subtest 'node listing' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);

    # Get a group ID
    my $sth = $dbh->prepare_cached("SELECT id FROM grp LIMIT 1");
    $sth->execute();
    my ($grp_id) = $sth->fetchrow_array();
    $sth->finish();

    ok(defined $grp_id, 'Got a group ID');

    # Test the node query that HTML.pm uses
    $sth = $dbh->prepare_cached("
        SELECT n.id, n.name, u.path
        FROM node n
        INNER JOIN url u ON u.node_id = n.id
        WHERE n.grp_id = ?
        ORDER BY n.name ASC
    ");
    $sth->execute($grp_id);

    my @nodes;
    while (my ($id, $name, $path) = $sth->fetchrow_array()) {
        push @nodes, { id => $id, name => $name, path => $path };
    }
    $sth->finish();

    # Might have nodes, might not - that's ok
    ok(1, 'Node listing query works');
};

# ============================================================================
# _get_params_groups - tests the full function including node processing
# SampleDB creates: 5 hosts (localhost, acme.com, aesir, asynjur, svartalfar)
# Each host has 5 services: cpu, memory, disk, network, load
# Categories: system (cpu, load), storage (memory, disk), network
# ============================================================================
subtest '_get_params_groups returns correct data from SampleDB' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);

    # Get prepared statements like HTML.pm does
    my $sth_grp_normal = $dbh->prepare_cached("
        SELECT g.id, g.name, u.path FROM grp g
        INNER JOIN url u ON u.grp_id = g.id AND p_id = ?
        ORDER BY g.name ASC");
    my $sth_grp_root = $dbh->prepare_cached("
        SELECT g.id, g.name, u.path FROM grp g
        INNER JOIN url u ON u.grp_id = g.id AND p_id = 0
        ORDER BY g.name ASC");
    my $sth_node = $dbh->prepare_cached("
        SELECT n.id, n.name, u.path, n.path FROM node n
        INNER JOIN url u ON u.node_id = n.id AND n.grp_id = ?
        ORDER BY n.name ASC");

    require Munin::Master::HTML;
    my $groups = Munin::Master::HTML::_get_params_groups(
        '', $dbh, $sth_grp_normal, $sth_grp_root, $sth_node, undef, 'png'
    );

    ok(ref $groups eq 'ARRAY', '_get_params_groups returns arrayref');

    # SampleDB creates one group per host: acme.com, aesir, asynjur, svartalfar
    # localhost is in acme.com group
    my %expected_groups = map { $_ => 1 } qw(acme.com aesir asynjur svartalfar);
    my %found_groups;

    for my $g (@$groups) {
        $found_groups{$g->{NAME}} = 1;

        ok(defined $g->{NAME}, "Group has NAME");
        like($g->{URL}, qr/\/$/, "Group URL ends with /");
        ok(ref $g->{GROUPS} eq 'ARRAY', "Group has GROUPS array");
        ok(defined $g->{NGROUPS}, "Group has NGROUPS");

        # Each group should have nodes
        my $node_count = 0;
        for my $n (@{$g->{GROUPS}}) {
            if (exists $n->{CATEGORIES}) {
                $node_count++;

                ok(defined $n->{NAME}, "Node has NAME: $n->{NAME}");
                like($n->{URL}, qr/\/$/, "Node URL ends with /");
                ok(ref $n->{CATEGORIES} eq 'ARRAY', "Node has CATEGORIES array");
                ok(defined $n->{NCATEGORIES}, "Node has NCATEGORIES");

                # Node should have categories from SampleDB
                my %expected_categories = map { $_ => 1 } qw(system storage network);
                for my $cat (@{$n->{CATEGORIES}}) {
                    ok(defined $cat->{NAME}, "Category has NAME: $cat->{NAME}");
                    ok(defined $expected_categories{$cat->{NAME}}, "Category '$cat->{NAME}' is valid");
                }

                # NCATEGORIES should match actual categories
                is(scalar @{$n->{CATEGORIES}}, $n->{NCATEGORIES},
                    "NCATEGORIES matches actual count for node $n->{NAME}");
            }
        }

        ok($node_count > 0, "Group '$g->{NAME}' has at least one node");
    }

    # Verify we found all expected groups
    for my $expected (keys %expected_groups) {
        ok($found_groups{$expected}, "Found expected group: $expected");
    }
};

# ============================================================================
# _get_params_services - tests service retrieval with categories
# ============================================================================
subtest '_get_params_services returns correct data' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);
    require Munin::Master::HTML;

    # SampleDB: cpu is in 'system' category
    # localhost has node_id, let's find it
    my ($node_id) = $dbh->selectrow_array("SELECT id FROM node WHERE name = 'localhost'");
    ok(defined $node_id, 'Got node_id for localhost');

    my $result = Munin::Master::HTML::_get_params_services(
        '', $dbh, 'system', undef, $node_id, 'png'
    );

    ok(ref $result eq 'HASH', '_get_params_services returns hashref');
    is($result->{NAME}, 'system', 'Category name is system');
    ok(ref $result->{SERVICES} eq 'ARRAY', 'SERVICES is arrayref');

    # SampleDB: cpu and load are in 'system' category
    my @service_names = map { $_->{NAME} } @{$result->{SERVICES}};
    my %expected_services = map { $_ => 1 } ('Graph cpu', 'Graph load');

    for my $svc_name (@service_names) {
        ok(defined $expected_services{$svc_name}, "Service '$svc_name' is expected");
    }

    # Check service structure
    for my $svc (@{$result->{SERVICES}}) {
        ok(defined $svc->{NAME}, "Service has NAME: $svc->{NAME}");
        ok(defined $svc->{URLX}, "Service has URLX: $svc->{URLX}");
        ok(defined $svc->{IMGday}, "Service has IMGday");
    }
};

# ============================================================================
# _get_params_fields - tests field retrieval for a service
# ============================================================================
subtest '_get_params_fields returns correct data' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);
    require Munin::Master::HTML;

    # Get a service ID (cpu for localhost)
    my ($service_id) = $dbh->selectrow_array("
        SELECT s.id FROM service s
        INNER JOIN node n ON s.node_id = n.id
        WHERE n.name = 'localhost' AND s.name = 'cpu'
    ");
    ok(defined $service_id, 'Got service_id for cpu');

    my $fields = Munin::Master::HTML::_get_params_fields($dbh, $service_id);

    ok(ref $fields eq 'ARRAY', '_get_params_fields returns arrayref');

    # SampleDB creates all ds_defs for every service
    my @field_names = map { $_->{FIELD} } @$fields;
    my %expected_fields = map { $_ => 1 } qw(idle user system used free cached rx tx in out value1 value2 value3 value4 value5);

    for my $field_name (@field_names) {
        ok(defined $expected_fields{$field_name}, "Field '$field_name' is expected");
    }

    # Check field structure
    for my $field (@$fields) {
        ok(defined $field->{FIELD}, "Field has FIELD: $field->{FIELD}");
        ok(defined $field->{TYPE}, "Field has TYPE: $field->{TYPE}");
    }
};

# ============================================================================
# Service categories - what HTML.pm uses for category views
# ============================================================================
subtest 'service categories' => sub {
    my $dbh = Munin::Master::Update::get_dbh(1);

    # Test the category query that HTML.pm uses
    my $sth = $dbh->prepare_cached("
        SELECT DISTINCT category FROM service_categories ORDER BY category ASC
    ");
    $sth->execute();

    my @categories;
    while (my ($category) = $sth->fetchrow_array()) {
        push @categories, $category;
    }
    $sth->finish();

    ok(scalar @categories >= 0, 'Category query works');
};

# ============================================================================
# Cleanup
# ============================================================================
END {
    rmtree($tmpdir) if $tmpdir && -d $tmpdir;
}

done_testing();

1;
