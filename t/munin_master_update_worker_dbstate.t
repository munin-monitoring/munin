use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::Differences;
use DBI;
use File::Temp qw(tempfile);

# Load real UpdateWorker
use Munin::Master::UpdateWorker;

# ============================================================================
# SETUP: In-memory SQLite database
# ============================================================================

my ($tempfh, $tempfile) = tempfile(CLEANUP => 1);
close $tempfh;

my $dbh = DBI->connect("dbi:SQLite:dbname=$tempfile", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
    PrintError => 0,
});

# Create schema matching production
$dbh->do("CREATE TABLE IF NOT EXISTS service (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id INTEGER NOT NULL,
    name VARCHAR NOT NULL
)");
$dbh->do("CREATE TABLE IF NOT EXISTS service_attr (
    id INTEGER REFERENCES service(id),
    name VARCHAR NOT NULL,
    value VARCHAR,
    PRIMARY KEY (id, name)
)");
$dbh->do("CREATE TABLE IF NOT EXISTS ds (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    service_id INTEGER REFERENCES service(id),
    name VARCHAR NOT NULL,
    ordr INTEGER DEFAULT 0
)");
$dbh->do("CREATE TABLE IF NOT EXISTS ds_attr (
    id INTEGER REFERENCES ds(id),
    name VARCHAR NOT NULL,
    value VARCHAR,
    PRIMARY KEY (id, name)
)");
$dbh->do("CREATE TABLE IF NOT EXISTS service_categories (
    id INTEGER REFERENCES service(id),
    category VARCHAR NOT NULL,
    PRIMARY KEY (id, category)
)");
$dbh->do("CREATE TABLE IF NOT EXISTS url (
    id INTEGER,
    type VARCHAR,
    path VARCHAR,
    PRIMARY KEY (id, type)
)");

# ============================================================================
# Create test worker using real UpdateWorker
# ============================================================================
# _db_service, _db_ds_update, _db_diff_attrs only need dbh and node_id

my $worker = bless { dbh => $dbh, node_id => 1 }, 'Munin::Master::UpdateWorker';

# Helper to get full service state
sub get_service_state {
    my ($service_id) = @_;

    my %state;

    # Get service_attr
    my $sth = $dbh->prepare("SELECT name, value FROM service_attr WHERE id = ? ORDER BY name");
    $sth->execute($service_id);
    my $rows = $sth->fetchall_arrayref({});
    $state{service_attr} = { map { $_->{name} => $_->{value} } @$rows };

    # Get ds and ds_attr
    $sth = $dbh->prepare("SELECT ds.id, ds.name as ds_name, ds_attr.name as attr_name, ds_attr.value as attr_value
        FROM ds LEFT JOIN ds_attr ON ds.id = ds_attr.id
        WHERE ds.service_id = ? ORDER BY ds.name, ds_attr.name");
    $sth->execute($service_id);
    $state{ds} = {};
    while (my $row = $sth->fetchrow_hashref()) {
        $state{ds}{$row->{ds_name}}{id} = $row->{id};
        $state{ds}{$row->{ds_name}}{attrs}{$row->{attr_name}} = $row->{attr_value}
            if defined $row->{attr_name};
    }

    return \%state;
}

# ============================================================================
# TEST SUITE: Plugin lifecycle scenarios
# ============================================================================

# Scenario 1: Fresh plugin - first config
subtest 'Scenario 1: Fresh plugin install' => sub {
    $dbh->do("DELETE FROM service WHERE node_id = 1 AND name = 'cpu'");
    $dbh->do("DELETE FROM ds WHERE service_id IN (SELECT id FROM service WHERE node_id = 1)");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("DELETE FROM service_attr");

    my ($svc_id) = $worker->_db_service('cpu',
        { graph_title => 'CPU Usage', graph_category => 'system' },
        { user => { label => 'User', type => 'GAUGE' }, idle => { label => 'Idle', type => 'GAUGE' } }
    );

    my $state = get_service_state($svc_id);

    is($state->{service_attr}{graph_title}, 'CPU Usage', "graph_title set");
    is($state->{service_attr}{graph_category}, 'system', "graph_category set");
    is(scalar keys %{$state->{ds}}, 2, "2 datasources created");
    is($state->{ds}{user}{attrs}{label}, 'User', "user.label set");
    is($state->{ds}{user}{attrs}{type}, 'GAUGE', "user.type set");
    is($state->{ds}{idle}{attrs}{label}, 'Idle', "idle.label set");
};

# Scenario 2: Plugin update - change label
subtest 'Scenario 2: Plugin update - change label' => sub {
    my ($svc_id) = $worker->_db_service('cpu',
        { graph_title => 'CPU Usage', graph_category => 'system' },
        { user => { label => 'User CPU', type => 'GAUGE' }, idle => { label => 'Idle', type => 'GAUGE' } }
    );

    my $state = get_service_state($svc_id);

    is($state->{ds}{user}{attrs}{label}, 'User CPU', "user.label updated");
    is($state->{ds}{idle}{attrs}{label}, 'Idle', "idle.label unchanged");
};

# Scenario 3: Plugin update - change type
subtest 'Scenario 3: Plugin update - change type' => sub {
    my ($svc_id) = $worker->_db_service('cpu',
        { graph_title => 'CPU Usage', graph_category => 'system' },
        { user => { label => 'User CPU', type => 'DERIVE', min => '0' }, idle => { label => 'Idle', type => 'GAUGE' } }
    );

    my $state = get_service_state($svc_id);

    is($state->{ds}{user}{attrs}{type}, 'DERIVE', "user.type changed to DERIVE");
    is($state->{ds}{user}{attrs}{min}, '0', "user.min added");
    is($state->{ds}{idle}{attrs}{type}, 'GAUGE', "idle.type unchanged");
};

# Scenario 4: Plugin update - add new field
subtest 'Scenario 4: Plugin update - add new field' => sub {
    my ($svc_id) = $worker->_db_service('cpu',
        { graph_title => 'CPU Usage', graph_category => 'system' },
        {
            user => { label => 'User CPU', type => 'DERIVE', min => '0' },
            idle => { label => 'Idle', type => 'GAUGE' },
            system => { label => 'System', type => 'DERIVE', min => '0' },
        }
    );

    my $state = get_service_state($svc_id);

    is(scalar keys %{$state->{ds}}, 3, "3 datasources now");
    is($state->{ds}{system}{attrs}{label}, 'System', "new system.field added");
    is($state->{ds}{system}{attrs}{type}, 'DERIVE', "system.type set");
};

# Scenario 5: Plugin update - remove field
subtest 'Scenario 5: Plugin update - remove field' => sub {
    my ($svc_id) = $worker->_db_service('cpu',
        { graph_title => 'CPU Usage', graph_category => 'system' },
        {
            user => { label => 'User CPU', type => 'DERIVE', min => '0' },
            # idle removed
            system => { label => 'System', type => 'DERIVE', min => '0' },
        }
    );

    my $state = get_service_state($svc_id);

    is(scalar keys %{$state->{ds}}, 2, "2 datasources (idle removed)");
    ok(!exists $state->{ds}{idle}, "idle field gone");
    ok(exists $state->{ds}{user}, "user field still exists");
    ok(exists $state->{ds}{system}, "system field still exists");
};

# Scenario 6: Plugin update - remove attribute from field
subtest 'Scenario 6: Plugin update - remove attribute from field' => sub {
    my ($svc_id) = $worker->_db_service('cpu',
        { graph_title => 'CPU Usage', graph_category => 'system' },
        {
            user => { label => 'User CPU', type => 'DERIVE' },  # min removed
            system => { label => 'System', type => 'DERIVE', min => '0' },
        }
    );

    my $state = get_service_state($svc_id);

    ok(!exists $state->{ds}{user}{attrs}{min}, "user.min removed");
    is($state->{ds}{user}{attrs}{label}, 'User CPU', "user.label still exists");
    is($state->{ds}{system}{attrs}{min}, '0', "system.min still exists");
};

# Scenario 7: Plugin update - change graph_title
subtest 'Scenario 7: Plugin update - change graph_title' => sub {
    my ($svc_id) = $worker->_db_service('cpu',
        { graph_title => 'CPU Utilization', graph_category => 'system' },
        { user => { label => 'User CPU', type => 'DERIVE' } }
    );

    my $state = get_service_state($svc_id);

    is($state->{service_attr}{graph_title}, 'CPU Utilization', "graph_title updated");
};

# Scenario 8: Plugin update - change graph_category
subtest 'Scenario 8: Plugin update - change graph_category' => sub {
    my ($svc_id) = $worker->_db_service('cpu',
        { graph_title => 'CPU Utilization', graph_category => 'performance' },
        { user => { label => 'User CPU', type => 'DERIVE' } }
    );

    my $state = get_service_state($svc_id);

    is($state->{service_attr}{graph_category}, 'performance', "graph_category updated");
};

# Scenario 9: Multiple fields with complex attribute changes
subtest 'Scenario 9: Complex multi-field attribute changes' => sub {
    $dbh->do("DELETE FROM service WHERE node_id = 1 AND name = 'complex'");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("DELETE FROM ds");

    # Initial state
    my ($svc_id) = $worker->_db_service('complex',
        { graph_title => 'Complex' },
        {
            a => { label => 'A', type => 'GAUGE', min => '0', max => '100' },
            b => { label => 'B', type => 'GAUGE' },
            c => { label => 'C', type => 'COUNTER' },
        }
    );

    # Update: change a.min, remove a.max, change b.type, remove c
    ($svc_id) = $worker->_db_service('complex',
        { graph_title => 'Complex' },
        {
            a => { label => 'A', type => 'GAUGE', min => '10' },  # min changed, max removed
            b => { label => 'B', type => 'DERIVE' },               # type changed
            # c removed
            d => { label => 'D', type => 'GAUGE' },               # new field
        }
    );

    my $state = get_service_state($svc_id);

    is($state->{ds}{a}{attrs}{min}, '10', "a.min updated");
    ok(!exists $state->{ds}{a}{attrs}{max}, "a.max removed");
    is($state->{ds}{b}{attrs}{type}, 'DERIVE', "b.type changed");
    ok(!exists $state->{ds}{c}, "c removed");
    is($state->{ds}{d}{attrs}{label}, 'D', "d added");
};

# Scenario 10: All fields removed then re-added
subtest 'Scenario 10: Remove all fields then re-add' => sub {
    $dbh->do("DELETE FROM service WHERE node_id = 1 AND name = 'purge_test'");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("DELETE FROM ds");

    my ($svc_id) = $worker->_db_service('purge_test',
        { graph_title => 'Purge Test' },
        { field1 => { label => 'F1' }, field2 => { label => 'F2' } }
    );

    # Remove all fields
    ($svc_id) = $worker->_db_service('purge_test',
        { graph_title => 'Purge Test' },
        {}  # no fields
    );

    my $state = get_service_state($svc_id);
    is(scalar keys %{$state->{ds}}, 0, "All fields removed");

    # Re-add fields
    ($svc_id) = $worker->_db_service('purge_test',
        { graph_title => 'Purge Test' },
        { field1 => { label => 'F1 New' } }
    );

    $state = get_service_state($svc_id);
    is(scalar keys %{$state->{ds}}, 1, "Field re-added");
    is($state->{ds}{field1}{attrs}{label}, 'F1 New', "Re-added field has correct attrs");
};

# Scenario 11: Empty config (all fields removed)
subtest 'Scenario 11: Plugin with no fields' => sub {
    $dbh->do("DELETE FROM service WHERE node_id = 1 AND name = 'empty'");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("DELETE FROM ds");

    my ($svc_id) = $worker->_db_service('empty',
        { graph_title => 'Empty' },
        {}  # no fields
    );

    my $state = get_service_state($svc_id);

    is(scalar keys %{$state->{ds}}, 0, "No datasources");
    is($state->{service_attr}{graph_title}, 'Empty', "Service attr still set");
};

# Scenario 12: Service attributes preserved across field updates
subtest 'Scenario 12: Service attrs independent of field changes' => sub {
    $dbh->do("DELETE FROM service WHERE node_id = 1 AND name = 'independent'");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("DELETE FROM ds");
    $dbh->do("DELETE FROM service_attr");

    my ($svc_id) = $worker->_db_service('independent',
        { graph_title => 'Original', update_rate => '300' },
        { x => { label => 'X' } }
    );

    # Update only fields, not service_attr
    ($svc_id) = $worker->_db_service('independent',
        { graph_title => 'Original', update_rate => '300' },
        { x => { label => 'X New' }, y => { label => 'Y' } }
    );

    my $state = get_service_state($svc_id);

    is($state->{service_attr}{graph_title}, 'Original', "graph_title unchanged");
    is($state->{service_attr}{update_rate}, '300', "update_rate unchanged");
    is($state->{ds}{x}{attrs}{label}, 'X New', "field x updated");
    is($state->{ds}{y}{attrs}{label}, 'Y', "field y added");
};

done_testing();

1;
