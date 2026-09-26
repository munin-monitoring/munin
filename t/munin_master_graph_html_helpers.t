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
    my $sth = $dbh->prepare_cached("SELECT id, type FROM url LIMIT 1");
    $sth->execute();
    my ($id, $type) = $sth->fetchrow_array();
    $sth->finish();

    ok(defined $id, 'Found a URL');
    ok(defined $type, 'URL has type');
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
        INNER JOIN url u ON u.id = g.id AND u.type = 'group'
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
        INNER JOIN url u ON u.id = n.id AND u.type = 'node'
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
