use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::Differences;
use DBI;
use File::Temp qw(tempfile);

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
# Mock UpdateWorker with full _db_service logic
# ============================================================================

package MockWorker;

sub new {
    my ($class, $dbh, $node_id) = @_;
    return bless { dbh => $dbh, node_id => $node_id }, $class;
}

sub _get_last_insert_id {
    my $self = shift;
    my $table = shift;
    return $self->{dbh}->last_insert_id(undef, undef, undef, 'id');
}

sub _db_diff_attrs {
    my ($self, $table, $id_col, $id, $attrs_old, $attrs_new) = @_;
    my $dbh = $self->{dbh};

    my %allowed = (
        'service_attr.id' => 1,
        'ds_attr.id' => 1,
    );
    die "_db_diff_attrs: invalid table '$table' id_col '$id_col'"
        unless $allowed{"$table.$id_col"};

    my $sth_up = $dbh->prepare_cached("UPDATE $table SET value = ? WHERE $id_col = ? AND name = ?");
    my $sth_ins = $dbh->prepare_cached("INSERT INTO $table ($id_col, name, value) VALUES (?, ?, ?)");
    my $sth_del = $dbh->prepare_cached("DELETE FROM $table WHERE $id_col = ? AND name = ?");

    for my $name (keys %$attrs_new) {
        my $value = $attrs_new->{$name};
        if (exists $attrs_old->{$name}) {
            if ($attrs_old->{$name} ne $value) {
                $sth_up->execute($value, $id, $name);
            }
        } else {
            $sth_ins->execute($id, $name, $value);
        }
    }

    for my $name (keys %$attrs_old) {
        unless (exists $attrs_new->{$name}) {
            $sth_del->execute($id, $name);
        }
    }
}

sub _db_ds_update {
    my ($self, $service_id, $field_name, $attrs_new, $attrs_old) = @_;
    my $dbh = $self->{dbh};

    my $sth_id = $dbh->prepare_cached("SELECT id FROM ds WHERE service_id = ? AND name = ?");
    $sth_id->execute($service_id, $field_name);
    my ($ds_id) = $sth_id->fetchrow_array();
    $sth_id->finish();

    if (!defined $ds_id) {
        my $sth_ds = $dbh->prepare_cached("INSERT INTO ds (service_id, name) VALUES (?, ?)");
        $sth_ds->execute($service_id, $field_name);
        $ds_id = $self->_get_last_insert_id($dbh, "ds");
    }

    $self->_db_diff_attrs('ds_attr', 'id', $ds_id, $attrs_old, $attrs_new);
    return $ds_id;
}

sub _db_service {
    my ($self, $plugin, $service_attr, $fields) = @_;
    my $dbh = $self->{dbh};
    my $node_id = $self->{node_id};

    # Get or create service
    my $sth_service_id = $dbh->prepare_cached("SELECT id FROM service WHERE node_id = ? AND name = ?");
    $sth_service_id->execute($node_id, $plugin);
    my ($service_id) = $sth_service_id->fetchrow_array();
    $sth_service_id->finish();

    if (!defined $service_id) {
        my $sth_service = $dbh->prepare_cached("INSERT INTO service (node_id, name) VALUES (?, ?)");
        $sth_service->execute($node_id, $plugin);
        $service_id = $self->_get_last_insert_id($dbh, "service");
    }

    # Read existing attrs
    my %service_attrs_old;
    my $sth_old = $dbh->prepare_cached("SELECT name, value FROM service_attr WHERE id = ?");
    $sth_old->execute($service_id);
    while (my ($n, $v) = $sth_old->fetchrow_array()) {
        $service_attrs_old{$n} = $v;
    }
    $sth_old->finish();

    my %fields_old;
    my $sth_fields_old = $dbh->prepare_cached("SELECT ds.name as field, ds_attr.name as attr, ds_attr.value FROM ds
        LEFT OUTER JOIN ds_attr ON ds.id = ds_attr.id WHERE ds.service_id = ?");
    $sth_fields_old->execute($service_id);
    while (my ($field, $attr, $val) = $sth_fields_old->fetchrow_array()) {
        $fields_old{$field}{$attr} = $val if defined $attr;
    }
    $sth_fields_old->finish();

    # Diff service_attr
    $self->_db_diff_attrs('service_attr', 'id', $service_id, \%service_attrs_old, $service_attr);

    # Diff ds_attr for each field
    my %ds_ids;
    for my $field_name (keys %$fields) {
        my $attrs_new = $fields->{$field_name};
        my $attrs_old = $fields_old{$field_name} // {};
        my $ds_id = $self->_db_ds_update($service_id, $field_name, $attrs_new, $attrs_old);
        $ds_ids{$field_name} = $ds_id;
    }

    # Delete datasources that are no longer in the config
    for my $old_field (keys %fields_old) {
        unless (exists $fields->{$old_field}) {
            my $sth_del = $dbh->prepare_cached('DELETE FROM ds WHERE service_id = ? AND name = ?');
            $sth_del->execute($service_id, $old_field);
        }
    }

    return ($service_id, \%service_attrs_old, \%fields_old, \%ds_ids);
}

sub _db_purge_stale_ds {
    my ($self, $service_id) = @_;
    my $dbh = $self->{dbh};

    my $sth = $dbh->prepare_cached('DELETE FROM ds WHERE service_id = ? AND NOT EXISTS (SELECT * FROM ds_attr WHERE ds_attr.id = ds.id)');
    $sth->execute($service_id);
}

package main;

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

my $worker = MockWorker->new($dbh, 1);

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

# Scenario 10: Purge stale datasources
subtest 'Scenario 10: Purge stale datasources' => sub {
    $dbh->do("DELETE FROM service WHERE node_id = 1 AND name = 'purge_test'");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("DELETE FROM ds");

    my ($svc_id) = $worker->_db_service('purge_test',
        { graph_title => 'Purge Test' },
        { field1 => { label => 'F1' }, field2 => { label => 'F2' } }
    );

    # Simulate field2 losing all attrs (should be purged)
    $dbh->do("DELETE FROM ds_attr WHERE id = (SELECT id FROM ds WHERE service_id = ? AND name = 'field2')", undef, $svc_id);

    $worker->_db_purge_stale_ds($svc_id);

    my $sth = $dbh->prepare("SELECT name FROM ds WHERE service_id = ? ORDER BY name");
    $sth->execute($svc_id);
    my @fields = map { $_->{name} } @{$sth->fetchall_arrayref({})};

    is(scalar @fields, 1, "Only 1 field remains after purge");
    is($fields[0], 'field1', "field1 remains, field2 purged");
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
