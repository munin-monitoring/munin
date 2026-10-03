use strict;
use warnings;

use lib qw(lib t/lib);

use Test::More;
use Test::Differences;
use File::Temp qw(tempdir);
use File::Slurp qw(read_file write_file);
use IPC::Open3;
use Symbol qw(gensym);
use DBI;

use TestUtils;
use Munin::Master::Schema;
use Munin::Master::Schema qw(CURRENT_SCHEMA_VERSION);

# Offline schema migration (spec: specs/01_OFFLINE_SCHEMA_MIGRATION.md).
#
# Fixture databases are built by executing t/lib/v0_schema.sql -- the
# golden pre-versioning DDL -- then seeded with v0 rows. The migration
# tool runs as a real subprocess (its CLI contract is part of what is
# under test: exit codes, output, connection precedence).
#
# The same file runs the pg matrix cell (MUNIN_TEST_DBDRIVER=pg): the
# fixtures go to TestPG scratch databases and the tool is pointed at
# them with --dburl/--dbdriver. No test logic differs per configuration.

my $driver = TestUtils::db_driver();    # 'SQLite' | 'Pg'
my $is_pg  = $driver eq 'Pg' ? 1 : 0;

#------------------------------------------------------------------------------
# Fixture plumbing
#------------------------------------------------------------------------------

# A fresh, empty database. Returns ($dbh, $target) where $target is
# what --dburl expects: a file path for sqlite, a database name for pg.
sub new_db {
    if ($is_pg) {
        require TestPG;
        my $dbname = TestPG::scratch_db()
            or BAIL_OUT('pg configuration but no usable postgres server');
        my $dbh = DBI->connect("dbi:Pg:dbname=$dbname", 'postgres', undef,
            { RaiseError => 1 });
        return ($dbh, $dbname);
    }
    require TestState;
    my $dir   = TestState::state_dir();
    my $file  = "$dir/datafile.sqlite";
    my $dbh   = DBI->connect("dbi:SQLite:dbname=$file", '', '',
        { RaiseError => 1 });
    $dbh->do('PRAGMA foreign_keys=ON');
    return ($dbh, $file);
}

# Execute the golden v0 DDL on a handle. pg flavor: the only per-driver
# difference in this DDL is SERIAL vs INTEGER primary keys.
sub apply_v0_sql {
    my ($dbh) = @_;
    my $sql = read_file('t/lib/v0_schema.sql');
    $sql =~ s/^--.*$//mg;
    $sql =~ s/id INTEGER PRIMARY KEY/id SERIAL PRIMARY KEY/g if $is_pg;
    for my $stmt (_split_sql($sql)) {
        $dbh->do($stmt);
    }
    return;
}

sub _split_sql {
    my ($sql) = @_;
    my @stmts;
    for my $chunk (split /;/, $sql) {
        $chunk =~ s/^\s+|\s+$//g;
        next unless length $chunk;
        push @stmts, $chunk;
    }
    return @stmts;
}

# Seed a consistent v0 dataset: grp -> node -> service -> ds chain,
# rrd:* ds_attr rows (one modern with rrd:field, one legacy without --
# pre-rrd:field files carry the DS name "42"), a plain attr, and a
# state row.
sub seed_v0_data {
    my ($dbh) = @_;
    $dbh->do("INSERT INTO grp (id, p_id, name, path) VALUES (0, NULL, '', '')");
    $dbh->do("INSERT INTO grp (id, p_id, name, path) VALUES (1, 0, 'g', 'g')");
    $dbh->do("INSERT INTO node (id, grp_id, name, path) VALUES (1, 1, 'n', 'g;n')");
    $dbh->do("INSERT INTO service (id, node_id, name) VALUES (1, 1, 'cpu')");
    $dbh->do("INSERT INTO ds (id, service_id, name, type) VALUES (1, 1, 'user', 'GAUGE')");
    $dbh->do("INSERT INTO ds (id, service_id, name, type) VALUES (2, 1, 'system', 'GAUGE')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (1, 'rrd:file', '/var/lib/munin/g/n/cpu.rrd')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (1, 'rrd:field', 'user-g')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (1, 'rrd:alias', 'cpu')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (2, 'rrd:file', '/var/lib/munin/g/n/cpu.rrd')");
    $dbh->do("INSERT INTO ds_attr (id, name, value) VALUES (1, 'warning', '80')");
    $dbh->do("INSERT INTO state (ds_id, last_epoch, last_value, alarm) VALUES (1, 1000, '42', 'ok')");
    return;
}

sub v0_fixture {
    # Returns ($dbh, $target): a seeded v0 database.
    my ($dbh, $target) = new_db();
    apply_v0_sql($dbh);
    seed_v0_data($dbh);
    return ($dbh, $target);
}

# Run script/munin-upgrade-db as a subprocess. MUNIN_DB* env vars are
# scrubbed from the child unless explicitly passed -- the connection
# precedence tests depend on the environment not leaking.
sub run_tool {
    my (%o) = @_;
    my @args = @{ $o{args} || [] };
    my @cmd  = ($^X, '-Ilib', '-Iblib/lib', 'script/munin-upgrade-db', @args);

    my %env = %ENV;
    delete $env{$_} for qw(MUNIN_DBURL MUNIN_DBDRIVER MUNIN_DBUSER
        MUNIN_DBPASSWD MUNIN_DB_JOURNAL_MODE MUNIN_DB_SYNCHRONOUS_MODE
        MUNIN_DB_AUTOCOMMIT MUNIN_CONF);
    %env = (%env, %{ $o{env} || {} });
    local %ENV = %env;

    my $err_fh = gensym();
    my $pid = open3(my $in, my $out_fh, $err_fh, @cmd);
    close $in;
    local $/;
    my $stdout = <$out_fh> // '';
    my $stderr = <$err_fh> // '';
    waitpid($pid, 0);
    my $rc = $? >> 8;
    return ($rc, $stdout . $stderr);
}

# Tool arguments for this driver. List form -- no shell splitting, so
# each flag and its value are separate elements.
sub tool_target_args {
    my ($target) = @_;
    return $is_pg
        ? ('--dburl', $target, '--dbdriver', 'Pg', '--dbuser', 'postgres')
        : ('--dburl', $target, '--dbdriver', 'SQLite');
}

# Catalog dump for "left unchanged" assertions: every schema object the
# migration could touch, in deterministic order.
sub schema_dump {
    my ($dbh) = @_;
    if ($is_pg) {
        my @bits;
        push @bits, map { "T:$_" } @{ $dbh->selectcol_arrayref(
            "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1") };
        push @bits, map { join('|', map { defined $_ ? $_ : '' } @$_) }
            @{ $dbh->selectall_arrayref(
                "SELECT table_name, column_name, data_type, is_nullable,
                        column_default
                 FROM information_schema.columns
                 WHERE table_schema='public'
                 ORDER BY table_name, ordinal_position") };
        push @bits, map { "$_->[0]|$_->[1]" }
            @{ $dbh->selectall_arrayref(
                "SELECT conrelid::regclass::text, pg_get_constraintdef(oid)
                 FROM pg_constraint WHERE connamespace='public'::regnamespace
                 ORDER BY 1, 2") };
        push @bits, map { "$_->[0]|$_->[1]" }
            @{ $dbh->selectall_arrayref(
                "SELECT tablename, indexdef FROM pg_indexes
                 WHERE schemaname='public' ORDER BY 1, 2") };
        return join("\n", @bits);
    }
    return join("\n", map { join('|', map { defined $_ ? $_ : '' } @$_) }
        @{ $dbh->selectall_arrayref(
            "SELECT type, name, COALESCE(sql, '') FROM sqlite_master
             ORDER BY type, name") });
}

# sqlite_master.sql text, whitespace-normalized: sqlite rewrites the
# stored CREATE text on ALTER TABLE ADD COLUMN (the new column is
# appended before the final paren), so punctuation placement differs
# from a from-scratch render while whitespace does not survive at all.
sub normalized_ddl_dump {
    my ($dbh) = @_;
    die "normalized_ddl_dump is sqlite-only" if $is_pg;
    return join("\n", map {
        my $s = $_->[1];
        $s =~ s/\s+//g;
        "$_->[0]: $s"
    } @{ $dbh->selectall_arrayref(
        "SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name") });
}

sub table_exists {
    my ($dbh, $name) = @_;
    if ($is_pg) {
        my ($n) = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = ?", undef, $name);
        return $n;
    }
    my ($n) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
        undef, $name);
    return $n;
}

# Live introspection vs the schema this code expects.
sub fingerprint_problems {
    my ($dbh) = @_;
    my $diff = Munin::Master::Schema::diff_schema(
        Munin::Master::Schema::introspect($dbh),
        Munin::Master::Schema::expected_schema($driver),
        $driver);
    return @{ $diff->{problems} };
}

sub problem_lines {
    return join('; ', map {
        my $w = join('.', grep { defined } @{$_}{qw(table col)});
        "$_->{kind} $w" . (defined $_->{detail} ? " ($_->{detail})" : '')
    } @_);
}

# The runtime get_dbh path, pointed at $target via env (get_dbh reads
# env || config). The verify memo is a process-global by design; tests
# reset it between cases.
sub runtime_get_dbh_dies {
    my ($target) = @_;
    require Munin::Master::Update;
    local $ENV{MUNIN_DBURL}    = $target;
    local $ENV{MUNIN_DBDRIVER} = $driver;
    local $ENV{MUNIN_DBUSER}   = $is_pg ? 'postgres' : '';
    Munin::Master::Schema::reset_verify_cache();
    my $err;
    eval { Munin::Master::Update::get_dbh(); 1 } or $err = $@;
    return $err;
}

sub runtime_get_dbh_ok {
    my ($target) = @_;
    require Munin::Master::Update;
    local $ENV{MUNIN_DBURL}    = $target;
    local $ENV{MUNIN_DBDRIVER} = $driver;
    local $ENV{MUNIN_DBUSER}   = $is_pg ? 'postgres' : '';
    Munin::Master::Schema::reset_verify_cache();
    my $dbh = eval { Munin::Master::Update::get_dbh() };
    return $dbh;
}

#------------------------------------------------------------------------------
# 1. Upgrade correctness: upgraded fixture == fresh bootstrap
#------------------------------------------------------------------------------

{
    my ($v0h, $v0target) = v0_fixture();
    my $dump_before = schema_dump($v0h);

    my ($rc, $out) = run_tool(args => [ tool_target_args($v0target) ]);
    is($rc, 0, "strict upgrade of v0 fixture exits 0") or diag $out;

    my ($freshh, $fresh_target) = new_db();
    Munin::Master::Schema::create_schema($freshh);
    Munin::Master::Schema::record($freshh, CURRENT_SCHEMA_VERSION,
        'bootstrap: full schema created');

    my $upgraded = Munin::Master::Schema::introspect($v0h);
    my $fresh    = Munin::Master::Schema::introspect($freshh);
    eq_or_diff($upgraded, $fresh,
        'upgraded fixture introspection is identical to a fresh bootstrap');

    my @problems = fingerprint_problems($v0h);
    ok(!@problems, 'upgraded fixture passes the fingerprint: '
        . problem_lines(@problems));

    # The spec's per-driver fingerprint evidence, asserted directly:
    # sqlite compares normalized sqlite_master text (FK clauses
    # included); pg compares information_schema FK join targets.
    if ($is_pg) {
        my $fk_dump = sub {
            my ($dbh) = @_;
            return join("\n", sort map { "$_->[0]|$_->[1]|$_->[2]|$_->[3]" }
                @{ $dbh->selectall_arrayref(
                    "SELECT tc.table_name, kcu.column_name,
                            ccu.table_name, ccu.column_name
                     FROM information_schema.table_constraints tc
                     JOIN information_schema.key_column_usage kcu
                       ON kcu.constraint_name = tc.constraint_name
                      AND kcu.table_schema = tc.table_schema
                     JOIN information_schema.constraint_column_usage ccu
                       ON ccu.constraint_name = tc.constraint_name
                      AND ccu.table_schema = tc.table_schema
                     WHERE tc.constraint_type = 'FOREIGN KEY'
                       AND tc.table_schema = 'public'") });
        };
        is($fk_dump->($v0h), $fk_dump->($freshh),
            'pg: FK join targets identical to fresh bootstrap');
    } else {
        is(normalized_ddl_dump($v0h), normalized_ddl_dump($freshh),
            'sqlite: normalized sqlite_master DDL identical to fresh bootstrap');
    }

    # The tool reported what it did
    like($out, qr/applied/, 'upgrade output narrates the applied steps');
    like($out, qr/ds_rrd/, 'upgrade output mentions the ds_rrd step');
}

#------------------------------------------------------------------------------
# 2. Data preservation
#------------------------------------------------------------------------------

{
    my ($v0h, $v0target) = v0_fixture();
    my ($rc, $out) = run_tool(args => [ tool_target_args($v0target) ]);
    is($rc, 0, 'data-preservation fixture upgrades cleanly') or diag $out;

    my $rrd = $v0h->selectall_arrayref(
        'SELECT ds_id, file, field, alias FROM ds_rrd ORDER BY ds_id');
    is(scalar @$rrd, 2, 'ds_rrd holds one row per migrated ds');
    is($rrd->[0][1], '/var/lib/munin/g/n/cpu.rrd', 'ds1 file mapping preserved');
    is($rrd->[0][2], 'user-g', 'ds1 rrd:field mapping preserved');
    is($rrd->[0][3], 'cpu',    'ds1 rrd:alias mapping preserved');
    is($rrd->[1][2], '42',
        "legacy mapping (no rrd:field) backfilled with the pre-rrd:field DS name '42'");

    my ($retired) = $v0h->selectrow_array(
        "SELECT COUNT(*) FROM ds_attr WHERE name LIKE 'rrd:%'");
    is($retired, 0, 'strict mode retired the migrated rrd:* attr rows');

    my ($warning) = $v0h->selectrow_array(
        "SELECT value FROM ds_attr WHERE id = 1 AND name = 'warning'");
    is($warning, '80', 'non-rrd ds_attr rows untouched');

    my ($not_deleted) = $v0h->selectrow_array(
        'SELECT COUNT(*) FROM ds WHERE deleted = 0');
    my ($total_ds) = $v0h->selectrow_array('SELECT COUNT(*) FROM ds');
    is($not_deleted, $total_ds, 'ds.deleted defaults to 0 on every row');

    my ($alarm, $last_value) = $v0h->selectrow_array(
        "SELECT alarm, last_value FROM state WHERE ds_id = 1");
    is($alarm, 'ok', 'state rows untouched (alarm)');
    is($last_value, '42', 'state rows untouched (last_value)');

    # A legacy rrd:field = "42" mapping survives as field '42'
    my ($legacy) = $v0h->selectrow_array(
        "SELECT field FROM ds_rrd WHERE ds_id = 2");
    is($legacy, '42', 'explicit legacy rrd:field=42 mapping preserved');
}

#------------------------------------------------------------------------------
# 2b. Audit trail + bootstrap path
#------------------------------------------------------------------------------

{
    my ($v0h, $v0target) = v0_fixture();
    my ($rc, $out) = run_tool(args => [ tool_target_args($v0target) ]);
    is($rc, 0, 'audit-trail fixture upgrades cleanly') or diag $out;

    my $hist = $v0h->selectall_arrayref(
        'SELECT version, tstp, comment FROM version_history ORDER BY id');
    ok(scalar @$hist >= 1, 'version_history holds audit rows');

    my @applied = grep { length($_->[2]) } @$hist;
    is(scalar @applied, scalar @$hist, 'every audit row has a non-empty comment');
    ok((grep { $_->[2] =~ /ds_rrd/ } @$hist),
        'audit trail records the ds_rrd step');
    my $now = time();
    ok((grep { $_->[1] > $now - 3600 && $_->[1] <= $now + 60 } @$hist),
        'audit epochs are sane unix timestamps');

    my ($maxv) = $v0h->selectrow_array('SELECT MAX(version) FROM version_history');
    is($maxv, CURRENT_SCHEMA_VERSION, 'MAX(version) equals CURRENT_SCHEMA_VERSION');
    is(Munin::Master::Schema::detect($v0h), CURRENT_SCHEMA_VERSION,
        'detect returns the version, not unversioned');

    # The bootstrap path writes its own audit row
    my ($freshh, $fresh_target) = new_db();
    require Munin::Master::Update;
    $freshh->{AutoCommit} = 0;    # _db_init commits internally
    Munin::Master::Update::_db_init(undef, $freshh);
    my ($boot_comment) = $freshh->selectrow_array(
        "SELECT comment FROM version_history WHERE version = " . CURRENT_SCHEMA_VERSION);
    like($boot_comment // '', qr/bootstrap: full schema created/,
        'bootstrap path records its own version_history row');
}

#------------------------------------------------------------------------------
# 3. Idempotency
#------------------------------------------------------------------------------

{
    my ($v0h, $v0target) = v0_fixture();
    my ($rc1) = run_tool(args => [ tool_target_args($v0target) ]);
    is($rc1, 0, 'first run upgrades');
    my ($rows1) = $v0h->selectrow_array('SELECT COUNT(*) FROM version_history');

    my ($rc2, $out2) = run_tool(args => [ tool_target_args($v0target) ]);
    is($rc2, 0, 'second run exits 0');
    like($out2, qr/up to date/, 'second run reports up to date');
    my ($rows2) = $v0h->selectrow_array('SELECT COUNT(*) FROM version_history');
    is($rows2, $rows1, 'second run appended no audit rows (did nothing)');
}

#------------------------------------------------------------------------------
# 4. Fail loud -- runtime (get_dbh / _db_init)
#------------------------------------------------------------------------------

{
    # v0 database through the real get_dbh path
    my ($v0h, $v0target) = v0_fixture();
    my $err = runtime_get_dbh_dies($v0target);
    like($err, qr/database schema mismatch/,
        'get_dbh dies on a v0 database');
    like($err, qr/v0 \(unversioned database\)/, 'message names the detected version');
    like($err, qr/required:\s+v1/, 'message names the required version');
    like($err, qr/munin-upgrade-db/, 'message names the fix');
    like($err, qr/last migration entry: \(none\)/,
        'unversioned database cites no migration entry');
    like($err, qr/risks data corruption/, 'message ends with the refusal');

    # _db_init refuses the same way (identical message shape)
    my $init_err;
    eval { Munin::Master::Update::_db_init(undef, $v0h); 1 } or $init_err = $@;
    like($init_err, qr/database schema mismatch/,
        '_db_init dies on a v0 database');
    like($init_err, qr/v0 \(unversioned database\)/,
        '_db_init message matches the verify message shape');

    # Downgrade: stamped newer than this code
    my ($newerh, $newer_target) = new_db();
    Munin::Master::Schema::create_schema($newerh);
    Munin::Master::Schema::record($newerh, 99, 'future schema marker');
    my $down_err = runtime_get_dbh_dies($newer_target);
    like($down_err, qr/downgrade unsupported/,
        'v99 database dies with the downgrade message');
    like($down_err, qr/back up the database and reinstall/,
        'downgrade message names the fix');
    like($down_err, qr/future schema marker/,
        'mismatch message cites the last version_history entry');

    # Versioned but old: the cited entry appears in the report
    my ($oldh, $old_target) = new_db();
    Munin::Master::Schema::create_schema($oldh);
    Munin::Master::Schema::record($oldh, 0, 'ancient audit entry');
    my $old_err = runtime_get_dbh_dies($old_target);
    like($old_err, qr/database schema mismatch/,
        'versioned-but-old database dies with the mismatch message');
    like($old_err, qr/ancient audit entry/,
        'mismatch message cites the newest version_history row');
    like($old_err, qr/munin-upgrade-db/, 'versioned mismatch still names the fix');

    # A fresh database passes verify (the caller bootstraps)
    my ($freshh, $fresh_target) = new_db();
    my $fresh_dbh = runtime_get_dbh_ok($fresh_target);
    ok($fresh_dbh, 'get_dbh on a fresh database succeeds (verify ok, caller bootstraps)');
}

#------------------------------------------------------------------------------
# 5. Fail loud -- tool (incompatible database, left untouched)
#------------------------------------------------------------------------------

{
    my ($brokenh, $broken_target) = new_db();
    apply_v0_sql($brokenh);
    $brokenh->do("DROP TABLE ds_attr");    # core table gone
    my $dump_before = schema_dump($brokenh);

    my ($rc, $out) = run_tool(args => [ tool_target_args($broken_target) ]);
    is($rc, 1, 'strict mode refuses a database with a missing core table');
    like($out, qr/missing core table: ds_attr/, 'diagnosis names the missing table');
    like($out, qr/incompatible/, 'diagnosis calls the database incompatible');
    is(schema_dump($brokenh), $dump_before,
        'refused database left byte-identical (catalog unchanged)');

    # --check on the same database: error, not "upgrade needed"
    ($rc, $out) = run_tool(args => [ '--check', tool_target_args($broken_target) ]);
    is($rc, 1, '--check exits 1 on an incompatible database');
}

#------------------------------------------------------------------------------
# 6. --check / --dry-run: exit codes, no writes
#------------------------------------------------------------------------------

{
    my ($v0h, $v0target) = v0_fixture();
    my $dump_before = schema_dump($v0h);

    my ($rc, $out) = run_tool(args => [ '--check', tool_target_args($v0target) ]);
    is($rc, 2, '--check on v0 exits 2 (upgrade needed)');
    like($out, qr/upgrade needed/, '--check reports the pending upgrade');
    like($out, qr/pending:/, '--check lists pending steps');
    is(schema_dump($v0h), $dump_before, '--check leaves the catalog unchanged');

    # --check on a fresh database: nothing to do
    my ($freshh, $fresh_target) = new_db();
    ($rc, $out) = run_tool(args => [ '--check', tool_target_args($fresh_target) ]);
    is($rc, 0, '--check on a fresh database exits 0');

    # --check on a current database: up to date
    my ($curh, $cur_target) = new_db();
    Munin::Master::Schema::create_schema($curh);
    Munin::Master::Schema::record($curh, CURRENT_SCHEMA_VERSION, 'bootstrap');
    ($rc, $out) = run_tool(args => [ '--check', tool_target_args($cur_target) ]);
    is($rc, 0, '--check on an up-to-date database exits 0');

    # --check on a newer-than-code database: error
    my ($newerh, $newer_target) = new_db();
    Munin::Master::Schema::create_schema($newerh);
    Munin::Master::Schema::record($newerh, 99, 'future');
    ($rc, $out) = run_tool(args => [ '--check', tool_target_args($newer_target) ]);
    is($rc, 1, '--check on a v99 database exits 1');

    # --dry-run: prints SQL, writes nothing
    ($rc, $out) = run_tool(args => [ '--dry-run', tool_target_args($v0target) ]);
    is($rc, 0, '--dry-run exits 0');
    like($out, qr/CREATE TABLE IF NOT EXISTS ds_rrd/,
        '--dry-run prints the ds_rrd DDL');
    like($out, qr/ALTER TABLE ds ADD COLUMN deleted/,
        '--dry-run prints the ds.deleted migration SQL');
    like($out, qr/steps that would apply/, '--dry-run reports the steps');
    is(schema_dump($v0h), $dump_before, '--dry-run leaves the catalog unchanged');
    ok(!table_exists($v0h, 'version_history'),
        '--dry-run did not create version_history');
    ok(!table_exists($v0h, 'ds_rrd'),
        '--dry-run did not create ds_rrd (nothing was written)');
}

#------------------------------------------------------------------------------
# 7. YOLO ladder (tool only)
#------------------------------------------------------------------------------

# (a) exact adoption: current-shaped schema without history
{
    my ($h, $target) = new_db();
    Munin::Master::Schema::create_schema($h);

    my ($rc, $out) = run_tool(args => [ '--yolo', tool_target_args($target) ]);
    is($rc, 0, 'yolo adopts a current-shaped schema without history') or diag $out;
    like($out, qr/yolo: adopted pre-existing v1-shaped schema/,
        'adoption is narrated');
    my ($comment) = $h->selectrow_array(
        'SELECT comment FROM version_history ORDER BY id DESC LIMIT 1');
    like($comment // '', qr/adopted pre-existing v1-shaped schema/,
        'adoption audit row recorded');

    # daemons never adopt: the runtime path refuses the pre-adoption
    # state of this fixture -- but a schema a human already adopted
    # offline (audit row stamped) is a legitimate v1 database
    my ($pre_h, $pre_target) = new_db();
    Munin::Master::Schema::create_schema($pre_h);
    my $pre_err = runtime_get_dbh_dies($pre_target);
    like($pre_err, qr/database schema mismatch/,
        'runtime dies on the pre-adoption (historyless) fixture');
    my $post_dbh = runtime_get_dbh_ok($target);
    ok($post_dbh, 'runtime accepts a database a human adopted offline (it is stamped v1)');
}

# (b) additive repair of a v0 fixture missing ds_rrd and ds.deleted
{
    my ($h, $target) = v0_fixture();
    my ($rc, $out) = run_tool(args => [ '--yolo', tool_target_args($target) ]);
    is($rc, 0, 'yolo repairs a v0 fixture additively') or diag $out;
    my @problems = fingerprint_problems($h);
    ok(!@problems, 'yolo-repaired schema verifies: ' . problem_lines(@problems));
    ok(table_exists($h, 'ds_rrd'), 'ds_rrd exists after yolo repair');
}

# (c) hard floor: no core tables, refused even with --yolo
{
    my ($h, $target) = new_db();
    $h->do("CREATE TABLE param (name VARCHAR PRIMARY KEY, value VARCHAR)");
    $h->do("CREATE TABLE whatever (id INTEGER)");
    my $dump_before = schema_dump($h);

    my ($rc, $out) = run_tool(args => [ '--yolo', tool_target_args($target) ]);
    is($rc, 1, 'yolo refuses a database with none of grp/node/service/ds');
    like($out, qr/would be a lie/, 'refusal explains why');
    is(schema_dump($h), $dump_before, 'refused database left unchanged');
}

# (d)+(f) additive-only guarantee + narrated audit comment
{
    my ($h, $target) = v0_fixture();
    $h->do("ALTER TABLE service ADD COLUMN legacy_note VARCHAR");
    my $dump_before = schema_dump($h);

    my ($rc, $out) = run_tool(args => [ '--yolo', tool_target_args($target) ]);
    is($rc, 0, 'yolo repair with extras exits 0') or diag $out;

    my ($kept_attr) = $h->selectrow_array(
        "SELECT COUNT(*) FROM ds_attr WHERE name LIKE 'rrd:%'");
    is($kept_attr, 4,
        'additive-only: seeded rrd:* ds_attr rows survive byte-identical');
    my ($kept_col) = $is_pg
        ? $h->selectrow_array(
            "SELECT COUNT(*) FROM information_schema.columns WHERE table_name='service' AND column_name='legacy_note'")
        : $h->selectrow_array(
            "SELECT COUNT(*) FROM pragma_table_info('service') WHERE name='legacy_note'");
    ok($kept_col, 'additive-only: unknown column survives');

    # (f) the audit comment lists every heuristic applied
    my ($comment) = $h->selectrow_array(
        'SELECT comment FROM version_history ORDER BY id DESC LIMIT 1');
    like($comment // '', qr/yolo: repaired/, 'audit comment is the yolo narrative');
    like($comment // '', qr/created missing tables \(ds_rrd\)/,
        'audit comment narrates created tables');
    like($comment // '', qr/added column deleted to ds/,
        'audit comment narrates added columns');
    like($comment // '', qr/mappings backfilled/,
        'audit comment carries the backfill count');
    like($comment // '', qr/legacy rrd:\* attr rows kept \(additive-only\)/,
        'audit comment narrates kept legacy rows');
    like($comment // '', qr/kept 1 unknown column \(service\.legacy_note\)/,
        'audit comment narrates the kept unknown column');
}

# (e) a yolo run that cannot satisfy verify still exits 1
{
    # A hand-modified url table missing its PRIMARY KEY column: the
    # column cannot be added additively (pk columns refuse in yolo), so
    # the ladder dies loudly and writes nothing.
    my ($h, $target) = v0_fixture();
    $h->do('DROP TABLE url');
    $h->do('CREATE TABLE url (grp_id INTEGER, node_id INTEGER, service_id INTEGER)');
    my $dump_before = schema_dump($h);

    my ($rc, $out) = run_tool(args => [ '--yolo', tool_target_args($target) ]);
    is($rc, 1, 'yolo exits 1 when additive repair cannot restore the schema');
    like($out, qr/missing primary key|missing_pk|refused/,
        'yolo refusal diagnoses the unrepairable divergence');
    is(schema_dump($h), $dump_before, 'failed yolo left the database unchanged');

    # the runtime path dies on this fixture too
    my $err = runtime_get_dbh_dies($target);
    like($err, qr/database schema mismatch/,
        'runtime dies on the unrepairable fixture');
}

# (g) --yolo --check plans without writing
{
    my ($h, $target) = v0_fixture();
    my $dump_before = schema_dump($h);

    my ($rc, $out) = run_tool(args => [ '--yolo', '--check', tool_target_args($target) ]);
    is($rc, 0, '--yolo --check exits 0 with a plan');
    like($out, qr/--yolo plan/, 'plan output is labeled');
    like($out, qr/create table|created missing/, 'plan lists the pending creation');
    is(schema_dump($h), $dump_before, '--yolo --check leaves the catalog unchanged');

    ($rc, $out) = run_tool(args => [ '--yolo', '--dry-run', tool_target_args($target) ]);
    is($rc, 0, '--yolo --dry-run exits 0 with a plan');
    is(schema_dump($h), $dump_before, '--yolo --dry-run leaves the catalog unchanged');
}

# the mocked-get_dbh runtime path dies on every yolo fixture state --
# daemons never adopt or repair
{
    my ($h, $target) = v0_fixture();
    my $err = runtime_get_dbh_dies($target);
    like($err, qr/database schema mismatch/,
        'runtime dies on a yolo (v0) fixture');
}

#------------------------------------------------------------------------------
# 8. Extra columns and constraints
#------------------------------------------------------------------------------

# Unconstrained extra column: warn, proceed (strict); keep, narrate (yolo)
{
    my ($h, $target) = v0_fixture();
    $h->do("ALTER TABLE service ADD COLUMN legacy_note VARCHAR");

    my ($rc, $out) = run_tool(args => [ tool_target_args($target) ]);
    is($rc, 0, 'strict upgrade proceeds past an unconstrained extra column') or diag $out;
    like($out, qr/warning: unconstrained extra column service\.legacy_note/,
        'strict mode warns about the unconstrained extra column');
    my ($col) = $h->selectrow_array(
        $is_pg
            ? "SELECT COUNT(*) FROM information_schema.columns WHERE table_name='service' AND column_name='legacy_note'"
            : "SELECT COUNT(*) FROM pragma_table_info('service') WHERE name='legacy_note'");
    ok($col, 'unconstrained extra column survives the upgrade');
}

# Constrained extra column: refuse in BOTH modes, left byte-identical
{
    my ($h, $target) = v0_fixture();
    $h->do("ALTER TABLE service ADD COLUMN legacy_note VARCHAR");
    $h->do("CREATE UNIQUE INDEX u_legacy ON service (legacy_note)");
    my $dump_before = schema_dump($h);

    my ($rc, $out) = run_tool(args => [ tool_target_args($target) ]);
    is($rc, 1, 'strict mode refuses a constrained extra column');
    like($out, qr/constrained extra column/, 'strict diagnosis names the constraint-backed column');
    is(schema_dump($h), $dump_before, 'strict refusal leaves the database byte-identical');

    ($rc, $out) = run_tool(args => [ '--yolo', tool_target_args($target) ]);
    is($rc, 1, 'yolo mode refuses a constrained extra column too');
    like($out, qr/constrained extra/, 'yolo diagnosis names the divergence');
    is(schema_dump($h), $dump_before, 'yolo refusal leaves the database byte-identical');
}

#------------------------------------------------------------------------------
# 9. Connection precedence: CLI arg > config file > default
#------------------------------------------------------------------------------

# CLI args beat the config file
{
    my ($cli_h, $cli_target) = v0_fixture();
    my ($cfg_h, $cfg_target) = v0_fixture();    # the config's db, decoy

    require TestState;
    my $conf_dir = TestState::state_dir();
    my $conf = "$conf_dir/munin.conf";
    if ($is_pg) {
        write_file($conf, "dburl $cfg_target\ndbdriver Pg\ndbuser postgres\n");
    } else {
        my ($decoy_dir) = $cfg_target =~ m{(.*)/datafile\.sqlite\z};
        write_file($conf, "dbdir $decoy_dir\n");
    }

    my @args = ('--config', $conf, tool_target_args($cli_target));
    my ($rc, $out) = run_tool(args => \@args);
    is($rc, 0, 'CLI-precedence run exits 0') or diag $out;

    my ($cli_versioned) = $cli_h->selectrow_array(
        'SELECT COUNT(*) FROM version_history');
    ok($cli_versioned, 'the --dburl fixture (CLI arg) was migrated');
    ok(!table_exists($cfg_h, 'version_history'),
        'the config-named database was NOT migrated');
}

# Config file beats compiled-in defaults
{
    my ($h, $target) = v0_fixture();
    require TestState;
    my $conf_dir = TestState::state_dir();
    my $conf = "$conf_dir/munin.conf";
    if ($is_pg) {
        write_file($conf, "dburl $target\ndbdriver Pg\ndbuser postgres\n");
    } else {
        my ($dbdir) = $target =~ m{(.*)/datafile\.sqlite\z};
        write_file($conf, "dbdir $dbdir\n");
    }

    my ($rc, $out) = run_tool(args => ['--config', $conf]);
    is($rc, 0, 'config-precedence run exits 0') or diag $out;
    my ($versioned) = $h->selectrow_array('SELECT COUNT(*) FROM version_history');
    ok($versioned,
        'the config-named database was migrated (config beats the compiled-in default)');
}

#------------------------------------------------------------------------------
# 10. pg cell: ALTER ADD CONSTRAINT + information_schema paths
#------------------------------------------------------------------------------

# FK retrofit: a v0 table missing its REFERENCES clause is repaired on
# both drivers (sqlite: table rebuild; pg: ALTER TABLE ADD
# CONSTRAINT), rows preserved.
{
    my ($h, $target) = new_db();
    apply_v0_sql($h);
    seed_v0_data($h);
    $h->do('DROP TABLE override');
    $h->do('CREATE TABLE override (ds_id INTEGER, name VARCHAR, value VARCHAR)');
    $h->do('CREATE UNIQUE INDEX pk_override ON override (ds_id, name)');
    $h->do("INSERT INTO override (ds_id, name, value) VALUES (1, 'warning', '30')");

    my ($rc, $out) = run_tool(args => [ tool_target_args($target) ]);
    is($rc, 0, 'FK retrofit upgrade exits 0') or diag $out;
    like($out, qr/FK retrofit/, 'retrofit step is narrated');

    my @problems = fingerprint_problems($h);
    ok(!@problems, 'retrofitted schema verifies: ' . problem_lines(@problems));

    my ($rows) = $h->selectrow_array('SELECT COUNT(*) FROM override');
    is($rows, 1, 'FK retrofit preserved the table rows');

    if ($is_pg) {
        my ($con) = $h->selectrow_array(
            "SELECT COUNT(*) FROM pg_constraint
             WHERE conrelid = 'override'::regclass AND contype = 'f'");
        ok($con, 'pg: ALTER TABLE ADD CONSTRAINT restored the REFERENCES clause');
    } else {
        my ($ddl) = $h->selectrow_array(
            "SELECT sql FROM sqlite_master WHERE name = 'override'");
        like($ddl // '', qr/REFERENCES ds\(id\)/,
            'sqlite: rebuilt table declares REFERENCES ds(id)');
    }
}

done_testing();

1;
