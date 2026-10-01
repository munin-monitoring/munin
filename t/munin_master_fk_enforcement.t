use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use File::Temp qw(tempfile);

# Prove FK enforcement from first principles, through the REAL get_dbh and
# _db_init: PRAGMA foreign_keys=ON must land, and the schema's FK/CHECK
# constraints must reject bad rows. Each case tries the actual statement
# against a real chain grp -> node -> service -> ds and asserts failure.
use Munin::Master::Update;

my ($fh, $dbfile) = tempfile(SUFFIX => '.sqlite', CLEANUP => 1);
close $fh;

local $ENV{MUNIN_DBURL}       = $dbfile;
local $ENV{MUNIN_DBDRIVER}    = 'SQLite';

my $dbh = Munin::Master::Update::get_dbh();
my $update = bless {}, 'Munin::Master::Update';
$update->_db_init($dbh);

# Valid chain: grp -> node -> service -> ds
$dbh->do("INSERT INTO grp (id, name) VALUES (1, 'g')");
$dbh->do("INSERT INTO node (id, grp_id, name, path) VALUES (1, 1, 'n', 'g;n')");
$dbh->do("INSERT INTO service (id, node_id, name) VALUES (1, 1, 'svc')");
$dbh->do("INSERT INTO ds (id, service_id, name) VALUES (1, 1, 'field')");

sub try {
	my ($sql, @bind) = @_;
	my $ok = eval { $dbh->do($sql, undef, @bind); 1 };
	return ($ok, $@);
}

# --- state table: ds_id FK -------------------------------------------------

my ($ok, $err) = try("INSERT INTO state (ds_id, last_epoch, last_value) VALUES (?, ?, ?)", 999999, 1, '1');
ok(!$ok, 'state row with orphan ds_id is rejected');
like($err, qr/FOREIGN KEY/i, '...rejected by FOREIGN KEY constraint');

($ok, $err) = try("INSERT INTO state (ds_id, last_epoch, last_value) VALUES (?, ?, ?)", 1, 1, '1');
ok($ok, "state row referencing existing ds is accepted" . ($ok ? '' : " ($err)"));

# --- state table: CHECK exactly one FK -------------------------------------

($ok, $err) = try("INSERT INTO state (ds_id, node_id) VALUES (?, ?)", undef, undef);
ok(!$ok, 'state row with both FKs NULL is rejected');
like($err, qr/CHECK/i, '...rejected by CHECK constraint');

# --- url table: grp_id FK --------------------------------------------------

($ok, $err) = try("INSERT INTO url (path, grp_id) VALUES (?, ?)", 'orphan', 999999);
ok(!$ok, 'url row with orphan grp_id is rejected');
like($err, qr/FOREIGN KEY/i, '...rejected by FOREIGN KEY constraint');

# --- deletes: children before parents, no cascade --------------------------

($ok, $err) = try("DELETE FROM node WHERE id = ?", 1);
ok(!$ok, 'deleting a node still referenced by a service is rejected');
like($err, qr/FOREIGN KEY/i, '...rejected by FOREIGN KEY constraint');

($ok, $err) = try("DELETE FROM ds WHERE id = ?", 1);
ok(!$ok, 'deleting a ds still referenced by state is rejected');
like($err, qr/FOREIGN KEY/i, '...rejected by FOREIGN KEY constraint');

# Explicit children-first order succeeds - the ordering UpdateWorker uses
$dbh->do("DELETE FROM state WHERE ds_id = 1");
$dbh->do("DELETE FROM ds WHERE id = 1");
pass('children-first delete order succeeds');

done_testing;
