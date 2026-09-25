use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::Exception;
use DBI;
use File::Temp qw(tempfile);

# Load real UpdateWorker
use Munin::Master::UpdateWorker;

# Create in-memory SQLite database for testing
sub create_test_db {
    my ($dbh) = @_;

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

    $dbh->do("CREATE TABLE IF NOT EXISTS state (
        id INTEGER,
        type VARCHAR,
        last_epoch INTEGER,
        last_value VARCHAR,
        prev_epoch INTEGER,
        prev_value VARCHAR,
        alarm VARCHAR,
        num_unknowns INTEGER DEFAULT 0,
        PRIMARY KEY (id, type)
    )");
}

# Create a real UpdateWorker object for testing
# _db_diff_attrs and _db_ds_update only need dbh and node_id
sub create_test_worker {
    my ($dbh) = @_;
    return bless { dbh => $dbh, node_id => 1 }, 'Munin::Master::UpdateWorker';
}

my ($dbh, $tempfile);
BEGIN {
    ($dbh, $tempfile) = tempfile(CLEANUP => 1);
    $dbh = DBI->connect("dbi:SQLite:dbname=$tempfile", "", "", {
        RaiseError => 1,
        AutoCommit => 1,
    });
    create_test_db($dbh);
}

my $worker = create_test_worker($dbh);

# ============================================================================
# TEST: Security gate
# ============================================================================

subtest 'Security gate rejects invalid table' => sub {
    dies_ok(sub {
        $worker->_db_diff_attrs('evil_table', 'id', 1, {}, {})
    }, "Dies on invalid table");

    like($@, qr/invalid table/, "Error message mentions invalid table");
};

subtest 'Security gate rejects invalid id_col' => sub {
    dies_ok(sub {
        $worker->_db_diff_attrs('service_attr', 'evil_col', 1, {}, {})
    }, "Dies on invalid id_col");

    like($@, qr/invalid/, "Error message mentions invalid");
};

subtest 'Security gate accepts valid combinations' => sub {
    lives_ok(sub {
        $worker->_db_diff_attrs('service_attr', 'id', 1, {}, {})
    }, "service_attr.id accepted");

    lives_ok(sub {
        $worker->_db_diff_attrs('ds_attr', 'id', 1, {}, {})
    }, "ds_attr.id accepted");
};

# ============================================================================
# TEST: _db_diff_attrs - INSERT operations
# ============================================================================

subtest 'Insert new attributes' => sub {
    $dbh->do("DELETE FROM service_attr");
    $dbh->do("INSERT INTO service (id, node_id, name) VALUES (100, 1, 'test')");

    $worker->_db_diff_attrs('service_attr', 'id', 100, {}, { foo => 'bar', baz => 'qux' });

    my $sth = $dbh->prepare("SELECT name, value FROM service_attr WHERE id = 100 ORDER BY name");
    $sth->execute();
    my @rows = @{$sth->fetchall_arrayref({})};

    is(scalar @rows, 2, "Inserted 2 attributes");
    is($rows[0]->{name}, 'baz', "First attr name");
    is($rows[0]->{value}, 'qux', "First attr value");
    is($rows[1]->{name}, 'foo', "Second attr name");
    is($rows[1]->{value}, 'bar', "Second attr value");
};

# ============================================================================
# TEST: _db_diff_attrs - UPDATE operations
# ============================================================================

subtest 'Update changed attributes' => sub {
    $dbh->do("DELETE FROM service_attr");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'keep', 'same')");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'change', 'old')");

    $worker->_db_diff_attrs('service_attr', 'id', 100,
        { keep => 'same', change => 'old' },
        { keep => 'same', change => 'new' }
    );

    my $sth = $dbh->prepare("SELECT name, value FROM service_attr WHERE id = 100 ORDER BY name");
    $sth->execute();
    my %result = map { $_->{name} => $_->{value} } @{$sth->fetchall_arrayref({})};

    is($result{keep}, 'same', "Unchanged attr preserved");
    is($result{change}, 'new', "Changed attr updated");
};

# ============================================================================
# TEST: _db_diff_attrs - DELETE operations
# ============================================================================

subtest 'Delete removed attributes' => sub {
    $dbh->do("DELETE FROM service_attr");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'keep', 'yes')");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'remove', 'bye')");

    $worker->_db_diff_attrs('service_attr', 'id', 100,
        { keep => 'yes', remove => 'bye' },
        { keep => 'yes' }
    );

    my $sth = $dbh->prepare("SELECT name, value FROM service_attr WHERE id = 100");
    $sth->execute();
    my @rows = @{$sth->fetchall_arrayref({})};

    is(scalar @rows, 1, "Only 1 attr remains");
    is($rows[0]->{name}, 'keep', "Kept attr is 'keep'");
};

# ============================================================================
# TEST: _db_diff_attrs - NO-OP for identical data
# ============================================================================

subtest 'No-op when data unchanged' => sub {
    $dbh->do("DELETE FROM service_attr");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'x', '1')");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'y', '2')");

    # Run diff with identical data
    $worker->_db_diff_attrs('service_attr', 'id', 100,
        { x => '1', y => '2' },
        { x => '1', y => '2' }
    );

    # Verify no changes happened (data still same)
    my $sth = $dbh->prepare("SELECT name, value FROM service_attr WHERE id = 100 ORDER BY name");
    $sth->execute();
    my %result = map { $_->{name} => $_->{value} } @{$sth->fetchall_arrayref({})};

    is($result{x}, '1', "x unchanged");
    is($result{y}, '2', "y unchanged");
};

# ============================================================================
# TEST: _db_diff_attrs - Empty inputs
# ============================================================================

subtest 'Empty old and new - no changes' => sub {
    $dbh->do("DELETE FROM service_attr");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'existing', 'keep')");

    $worker->_db_diff_attrs('service_attr', 'id', 100, {}, {});

    my $sth = $dbh->prepare("SELECT COUNT(*) FROM service_attr WHERE id = 100");
    $sth->execute();
    my ($cnt) = $sth->fetchrow_array();

    is($cnt, 1, "Existing attr preserved when both inputs empty");
};

subtest 'Populate from empty old' => sub {
    $dbh->do("DELETE FROM service_attr");

    $worker->_db_diff_attrs('service_attr', 'id', 100, {}, { a => '1', b => '2', c => '3' });

    my $sth = $dbh->prepare("SELECT COUNT(*) FROM service_attr WHERE id = 100");
    $sth->execute();
    my ($cnt) = $sth->fetchrow_array();

    is($cnt, 3, "All new attrs inserted");
};

subtest 'Clear all attrs' => sub {
    $dbh->do("DELETE FROM service_attr");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'x', '1')");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'y', '2')");

    $worker->_db_diff_attrs('service_attr', 'id', 100, { x => '1', y => '2' }, {});

    my $sth = $dbh->prepare("SELECT COUNT(*) FROM service_attr WHERE id = 100");
    $sth->execute();
    my ($cnt) = $sth->fetchrow_array();

    is($cnt, 0, "All attrs deleted");
};

# ============================================================================
# TEST: _db_ds_update - CREATE new datasource
# ============================================================================

subtest 'Create new datasource' => sub {
    $dbh->do("DELETE FROM ds WHERE service_id = 200");
    $dbh->do("INSERT INTO service (id, node_id, name) VALUES (200, 1, 'test_svc')");

    my $ds_id = $worker->_db_ds_update(200, 'field1', { label => 'Field One', type => 'GAUGE' }, {});

    ok(defined $ds_id, "Got ds_id");
    ok($ds_id > 0, "ds_id is positive");

    my $sth = $dbh->prepare("SELECT name FROM ds WHERE id = ?");
    $sth->execute($ds_id);
    my ($name) = $sth->fetchrow_array();
    is($name, 'field1', "Datasource name correct");

    # Verify attrs were created
    $sth = $dbh->prepare("SELECT name, value FROM ds_attr WHERE id = ? ORDER BY name");
    $sth->execute($ds_id);
    my %attrs = map { $_->{name} => $_->{value} } @{$sth->fetchall_arrayref({})};

    is($attrs{label}, 'Field One', "Label attr created");
    is($attrs{type}, 'GAUGE', "Type attr created");
};

# ============================================================================
# TEST: _db_ds_update - UPDATE existing datasource
# ============================================================================

subtest 'Update existing datasource attrs' => sub {
    $dbh->do("DELETE FROM ds WHERE service_id = 200");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("INSERT INTO ds (id, service_id, name) VALUES (500, 200, 'field1')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (500, 'label', 'Old Label')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (500, 'type', 'GAUGE')");

    my $ds_id = $worker->_db_ds_update(200, 'field1',
        { label => 'New Label', type => 'GAUGE' },  # new
        { label => 'Old Label', type => 'GAUGE' }   # old
    );

    is($ds_id, 500, "Returned existing ds_id");

    my $sth = $dbh->prepare("SELECT name, value FROM ds_attr WHERE id = 500 ORDER BY name");
    $sth->execute();
    my %attrs = map { $_->{name} => $_->{value} } @{$sth->fetchall_arrayref({})};

    is($attrs{label}, 'New Label', "Label updated");
    is($attrs{type}, 'GAUGE', "Type unchanged");
};

# ============================================================================
# BUG CATCH TEST: Missing old attrs should cause INSERT, not UPDATE
# ============================================================================

subtest 'BUG: New attr not in old should INSERT not UPDATE' => sub {
    $dbh->do("DELETE FROM ds WHERE service_id = 200");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("INSERT INTO ds (id, service_id, name) VALUES (501, 200, 'field2')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (501, 'label', 'Existing')");

    # Old has only 'label', new has 'label' + 'type'
    my $ds_id = $worker->_db_ds_update(200, 'field2',
        { label => 'Existing', type => 'GAUGE' },  # new
        { label => 'Existing' }                     # old - missing 'type'
    );

    my $sth = $dbh->prepare("SELECT name, value FROM ds_attr WHERE id = 501 ORDER BY name");
    $sth->execute();
    my %attrs = map { $_->{name} => $_->{value} } @{$sth->fetchall_arrayref({})};

    is(scalar keys %attrs, 2, "Both attrs exist");
    is($attrs{type}, 'GAUGE', "New attr 'type' was INSERTED");
};

# ============================================================================
# BUG CATCH TEST: Stale attrs should be deleted
# ============================================================================

subtest 'BUG: Old attr not in new should be DELETED' => sub {
    $dbh->do("DELETE FROM ds WHERE service_id = 200");
    $dbh->do("DELETE FROM ds_attr");
    $dbh->do("INSERT INTO ds (id, service_id, name) VALUES (502, 200, 'field3')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (502, 'label', 'Keep')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (502, 'stale', 'Delete me')");

    # Old has 'label' + 'stale', new has only 'label'
    my $ds_id = $worker->_db_ds_update(200, 'field3',
        { label => 'Keep' },              # new - no 'stale'
        { label => 'Keep', stale => 'Delete me' }  # old - has 'stale'
    );

    my $sth = $dbh->prepare("SELECT name FROM ds_attr WHERE id = 502");
    $sth->execute();
    my @names = map { $_->{name} } @{$sth->fetchall_arrayref({})};

    is(scalar @names, 1, "Only 1 attr remains");
    is($names[0], 'label', "Only 'label' remains, 'stale' deleted");
};

# ============================================================================
# TEST: ds_attr with empty values
# ============================================================================

subtest 'Handle empty string values' => sub {
    $dbh->do("DELETE FROM service_attr");

    $worker->_db_diff_attrs('service_attr', 'id', 100, {}, { empty => '', space => ' ' });

    my $sth = $dbh->prepare("SELECT name, value FROM service_attr WHERE id = 100 ORDER BY name");
    $sth->execute();
    my %attrs = map { $_->{name} => $_->{value} } @{$sth->fetchall_arrayref({})};

    is($attrs{empty}, '', "Empty string value stored");
    is($attrs{space}, ' ', "Space value stored");
};

# ============================================================================
# TEST: Multiple operations in sequence
# ============================================================================

subtest 'Complex diff scenario' => sub {
    $dbh->do("DELETE FROM service_attr");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'a', '1')");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'b', '2')");
    $dbh->do("INSERT INTO service_attr (id, name, value) VALUES (100, 'c', '3')");

    # old: a=1, b=2, c=3
    # new: a=1 (keep), b=99 (update), d=4 (insert), c removed (delete)
    $worker->_db_diff_attrs('service_attr', 'id', 100,
        { a => '1', b => '2', c => '3' },
        { a => '1', b => '99', d => '4' }
    );

    my $sth = $dbh->prepare("SELECT name, value FROM service_attr WHERE id = 100 ORDER BY name");
    $sth->execute();
    my %result = map { $_->{name} => $_->{value} } @{$sth->fetchall_arrayref({})};

    is(scalar keys %result, 3, "3 attrs total");
    is($result{a}, '1', "a kept");
    is($result{b}, '99', "b updated");
    is($result{d}, '4', "d inserted");
    ok(!exists $result{c}, "c deleted");
};

done_testing();

1;
