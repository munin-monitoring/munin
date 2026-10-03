package Munin::Master::Schema;

# Single source of truth for Munin's SQL schema.
#
# Everything that defines the schema lives here -- the DDL, the version
# constant, the audit-trail writer, introspection and the one v0->v1
# migration step -- and is shared by the two callers:
#
#   * the runtime bootstrap (Munin::Master::Update::_db_init): create a
#     virgin database, or verify the version and die. No migration
#     logic, ever.
#   * the offline migration tool (script/munin-upgrade-db): the ONLY
#     place schema evolution happens.
#
# The DDL is rendered from one canonical data structure (@TABLES), and
# the introspection expectations (expected_schema) are derived from the
# same structure -- the two can never drift.
#
# Schema versioning: version_history is both the version stamp
# (MAX(version)) and the human-readable audit trail of every migration
# a database has been through. It deliberately does not live in param:
# _db_params_update deletes and reinserts all param rows every cycle.

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(CURRENT_SCHEMA_VERSION);

use constant CURRENT_SCHEMA_VERSION => 1;

# Memoized verify() flag: handles are opened repeatedly and the check is
# one cheap query. Migration is offline by contract, so a process that
# verified once never observes a schema change underneath it.
my $VERIFIED;

#------------------------------------------------------------------------------
# Canonical schema
#
# Column tuple: [ name, type, opts ]
#   type: INTEGER | VARCHAR | TIMESTAMPTZ | NUMERIC | IDPK
#         IDPK renders "INTEGER PRIMARY KEY" (sqlite) or
#         "SERIAL PRIMARY KEY" (pg); the handle decides which.
#   opts: pk => part of the table-level PRIMARY KEY
#         unique => inline UNIQUE
#         notnull => 1
#         dflt => SQL literal text (as it appears in the DDL)
#         fk => [ reftable, [ refcols ] ]   (inline REFERENCES)
#
# Table hash: name, columns, optional table_pk / checks / indexes.
# indexes: [ { name, unique, cols } ] -- named CREATE [UNIQUE] INDEX.
#------------------------------------------------------------------------------

my @TABLES = (
    {   name    => 'param',
        columns => [
            [ 'name',  'VARCHAR', { pk => 1 } ],
            [ 'value', 'VARCHAR' ],
        ],
    },
    {   name    => 'grp',
        columns => [
            [ 'id',    'IDPK' ],
            [ 'p_id',  'INTEGER', { fk => [ 'grp', ['id'] ] } ],
            [ 'name',  'VARCHAR' ],
            [ 'path',  'VARCHAR' ],
        ],
        indexes => [ { name => 'r_g_grp', unique => 1, cols => [qw(p_id name)] } ],
    },
    {   name    => 'node',
        columns => [
            [ 'id',         'IDPK' ],
            [ 'grp_id',     'INTEGER', { fk => [ 'grp', ['id'] ] } ],
            [ 'name',       'VARCHAR' ],
            [ 'path',       'VARCHAR' ],
            [ 'spoolepoch', 'INTEGER' ],
        ],
        indexes => [ { name => 'r_n_grp', unique => 0, cols => ['grp_id'] } ],
    },
    {   name    => 'node_attr',
        columns => [
            [ 'id',    'INTEGER', { fk => [ 'node', ['id'] ] } ],
            [ 'name',  'VARCHAR' ],
            [ 'value', 'VARCHAR' ],
        ],
        indexes => [ { name => 'pk_node_attr', unique => 1, cols => [qw(id name)] } ],
    },
    {   name    => 'service',
        columns => [
            [ 'id',            'IDPK' ],
            [ 'node_id',       'INTEGER', { fk => [ 'node', ['id'] ] } ],
            [ 'name',          'VARCHAR' ],
            [ 'path',          'VARCHAR' ],
            [ 'service_title', 'VARCHAR' ],
            [ 'graph_info',    'VARCHAR' ],
            [ 'subgraphs',     'INTEGER' ],
        ],
        indexes => [
            { name => 'u_service_n_n', unique => 1, cols => [qw(node_id name)] },
            { name => 'r_s_node',      unique => 0, cols => ['node_id'] },
        ],
    },
    {   name    => 'service_attr',
        columns => [
            [ 'id',    'INTEGER', { fk => [ 'service', ['id'] ] } ],
            [ 'name',  'VARCHAR' ],
            [ 'value', 'VARCHAR' ],
        ],
        indexes => [ { name => 'pk_service_attr', unique => 1, cols => [qw(id name)] } ],
    },
    {   name    => 'service_categories',
        columns => [
            [ 'id',       'INTEGER', { fk => [ 'service', ['id'] ] } ],
            [ 'category', 'VARCHAR', { notnull => 1 } ],
        ],
        table_pk => [qw(id category)],
    },
    {   name    => 'ds',
        columns => [
            [ 'id',         'IDPK' ],
            [ 'service_id', 'INTEGER', { fk => [ 'service', ['id'] ] } ],
            [ 'name',       'VARCHAR' ],
            [ 'path',       'VARCHAR' ],
            [ 'type',       'VARCHAR', { dflt => "'GAUGE'" } ],
            [ 'ordr',       'INTEGER', { dflt => '0' } ],
            [ 'unknown',    'INTEGER', { dflt => '0' } ],
            [ 'warning',    'INTEGER', { dflt => '0' } ],
            [ 'critical',   'INTEGER', { dflt => '0' } ],
            [ 'deleted',    'INTEGER', { dflt => '0' } ],
        ],
        indexes => [ { name => 'r_d_service', unique => 0, cols => ['service_id'] } ],
    },
    {   name    => 'ds_attr',
        columns => [
            [ 'id',    'INTEGER', { fk => [ 'ds', ['id'] ] } ],
            [ 'name',  'VARCHAR' ],
            [ 'value', 'VARCHAR' ],
        ],
        indexes => [ { name => 'pk_ds_attr', unique => 1, cols => [qw(id name)] } ],
    },
    {   name    => 'ds_rrd',
        columns => [
            [ 'ds_id', 'INTEGER', { pk => 1, fk => [ 'ds', ['id'] ] } ],
            [ 'file',  'VARCHAR', { notnull => 1 } ],
            [ 'field', 'VARCHAR', { notnull => 1 } ],
            [ 'alias', 'VARCHAR' ],
        ],
    },
    {   name    => 'url',
        columns => [
            [ 'path',       'VARCHAR', { pk => 1 } ],
            [ 'grp_id',     'INTEGER', { fk => [ 'grp', ['id'] ] } ],
            [ 'node_id',    'INTEGER', { fk => [ 'node', ['id'] ] } ],
            [ 'service_id', 'INTEGER', { fk => [ 'service', ['id'] ] } ],
        ],
        checks => [ 'CAST((grp_id IS NOT NULL) AS INTEGER) + CAST((node_id IS NOT NULL) AS INTEGER) + CAST((service_id IS NOT NULL) AS INTEGER) = 1' ],
    },
    {   name    => 'state',
        columns => [
            [ 'ds_id',        'INTEGER', { fk => [ 'ds', ['id'] ] } ],
            [ 'node_id',      'INTEGER', { fk => [ 'node', ['id'] ] } ],
            [ 'last_epoch',   'INTEGER' ],
            [ 'last_value',   'VARCHAR' ],
            [ 'prev_epoch',   'INTEGER' ],
            [ 'prev_value',   'VARCHAR' ],
            [ 'alarm',        'VARCHAR' ],
            [ 'num_unknowns', 'INTEGER', { dflt => '0' } ],
            [ 'prev_alarm',   'VARCHAR' ],
            [ 'eval_value',   'VARCHAR' ],
            [ 'extinfo',      'VARCHAR' ],
        ],
        checks => [ 'CAST((ds_id IS NOT NULL) AS INTEGER) + CAST((node_id IS NOT NULL) AS INTEGER) = 1' ],
        indexes => [
            { name => 'pk_state_ds',   unique => 1, cols => ['ds_id'] },
            { name => 'pk_state_node', unique => 1, cols => ['node_id'] },
        ],
    },
    {   name    => 'stats',
        columns => [
            [ 'runid',    'VARCHAR', { notnull => 1 } ],
            [ 'tstp',     'TIMESTAMPTZ' ],
            [ 'type',     'VARCHAR' ],
            [ 'name',     'VARCHAR' ],
            [ 'duration', 'NUMERIC' ],
        ],
    },
    {   name    => 'contact',
        columns => [
            [ 'id',   'IDPK' ],
            [ 'name', 'VARCHAR', { unique => 1 } ],
        ],
    },
    {   name    => 'contact_attr',
        columns => [
            [ 'id',    'INTEGER', { fk => [ 'contact', ['id'] ] } ],
            [ 'name',  'VARCHAR' ],
            [ 'value', 'VARCHAR' ],
        ],
        indexes => [ { name => 'pk_contact_attr', unique => 1, cols => [qw(id name)] } ],
    },
    {   name    => 'notification_tracking',
        columns => [
            [ 'id',           'IDPK' ],
            [ 'contact_id',   'INTEGER', { fk => [ 'contact', ['id'] ] } ],
            [ 'service_id',   'INTEGER', { fk => [ 'service', ['id'] ] } ],
            [ 'severity',     'VARCHAR' ],
            [ 'sent_at',      'INTEGER' ],
            [ 'num_messages', 'INTEGER', { dflt => '0' } ],
        ],
        indexes => [ { name => 'u_notification_tracking', unique => 1, cols => [qw(contact_id service_id)] } ],
    },
    {   name    => 'override',
        columns => [
            [ 'ds_id', 'INTEGER', { fk => [ 'ds', ['id'] ] } ],
            [ 'name',  'VARCHAR' ],
            [ 'value', 'VARCHAR' ],
        ],
        indexes => [ { name => 'pk_override', unique => 1, cols => [qw(ds_id name)] } ],
    },
    {   name    => 'config_override',
        columns => [
            [ 'host_name',    'VARCHAR', { notnull => 1 } ],
            [ 'service_name', 'VARCHAR', { notnull => 1, dflt => "''" } ],
            [ 'field_name',   'VARCHAR', { notnull => 1, dflt => "''" } ],
            [ 'name',         'VARCHAR', { notnull => 1 } ],
            [ 'value',        'VARCHAR' ],
        ],
        table_pk => [qw(host_name service_name field_name name)],
    },
);

# version_history: written by record(), never by create_schema -- every
# write to the audit trail must be deliberate.
my $VERSION_HISTORY_TABLE = {
    name    => 'version_history',
    columns => [
        [ 'id',      'IDPK' ],
        [ 'version', 'INTEGER', { notnull => 1 } ],
        [ 'tstp',    'INTEGER', { notnull => 1 } ],
        [ 'comment', 'VARCHAR', { notnull => 1 } ],
    ],
};

# Tables the pre-versioning rename migrated: accepted by the v0
# acceptance check and renamed by migrate_v0_to_v1.
my $LEGACY_TABLES = [ 'notification' ];

my %TABLE_BY_NAME = map { $_->{name} => $_ } @TABLES;

my @CORE_TABLES = qw(grp node service ds ds_attr state);

#------------------------------------------------------------------------------
# Small helpers
#------------------------------------------------------------------------------

sub _driver {
    my ($dbh) = @_;
    return $dbh->{Driver}->{Name};
}

# Every table physically present in the database.
sub all_tables {
    my ($dbh) = @_;
    if (_driver($dbh) eq 'Pg') {
        return $dbh->selectcol_arrayref(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public'");
    }
    return $dbh->selectcol_arrayref(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'");
}

sub _table_set {
    my ($dbh) = @_;
    return { map { $_ => 1 } @{ all_tables($dbh) } };
}

# Column name => { type, notnull, dflt, pk } for one table (live db).
sub _column_set {
    my ($dbh, $table) = @_;
    if (_driver($dbh) eq 'Pg') {
        my $rows = $dbh->selectall_arrayref(
            "SELECT column_name, data_type, is_nullable, column_default
             FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = ?",
            undef, $table);
        return { map {
            $_->[0] => {
                type    => _pg_type($_->[1]),
                notnull => ($_->[2] || '') eq 'NO' ? 1 : 0,
                dflt    => _norm_dflt($_->[3]),
                pk      => 0,
            }
        } @$rows };
    }
    my $rows = $dbh->selectall_arrayref("PRAGMA table_info($table)");
    return { map {
        $_->[1] => {
            type    => $_->[2],
            notnull => $_->[3] + 0,
            dflt    => defined $_->[4] ? _norm_dflt($_->[4]) : undef,
            pk      => $_->[5] + 0,
        }
    } @$rows };
}

sub _pg_type {
    my ($t) = @_;
    return 'VARCHAR'       if ($t || '') eq 'character varying';
    return 'INTEGER'       if ($t || '') eq 'integer';
    return 'TIMESTAMPTZ'   if ($t || '') eq 'timestamp with time zone';
    return 'NUMERIC'       if ($t || '') eq 'numeric';
    return uc($t || '');
}

# Normalize a column default so sqlite and pg renderings compare equal:
# strip ::type casts, schema qualification and whitespace.
sub _norm_dflt {
    my ($d) = @_;
    return unless defined $d;
    $d =~ s/::[a-z][a-z ]*//gi;
    $d =~ s/'public\./'/g;
    $d =~ s/\s+//g;
    return $d;
}

# Execute one statement, recording it when the handle carries a
# private_munin_sql_log arrayref (the tool's --dry-run mode: statements
# are printed, then the transaction is rolled back -- no writes).
sub _do {
    my ($dbh, $sql, @bind) = @_;
    my $log = $dbh->{private_munin_sql_log};
    push @$log, @bind ? [ $sql, @bind ] : [ $sql ] if $log;
    $dbh->do($sql, undef, @bind);
    return;
}

sub _count {
    my ($dbh, $sql, @bind) = @_;
    my ($n) = $dbh->selectrow_array($sql, undef, @bind);
    return $n || 0;
}

#------------------------------------------------------------------------------
# DDL rendering
#------------------------------------------------------------------------------

sub _render_type {
    my ($type, $driver) = @_;
    return $driver eq 'Pg' ? 'SERIAL' : 'INTEGER' if $type eq 'IDPK';
    return $type;
}

sub _column_ddl {
    my ($col, $driver) = @_;
    my ($name, $type, $o) = @$col;
    $o ||= {};
    my $sql = "$name " . _render_type($type, $driver);
    $sql .= ' PRIMARY KEY' if $o->{pk} || $type eq 'IDPK';
    $sql .= ' UNIQUE'      if $o->{unique};
    $sql .= ' NOT NULL'    if $o->{notnull};
    $sql .= ' DEFAULT ' . $o->{dflt} if defined $o->{dflt};
    if ($o->{fk}) {
        $sql .= " REFERENCES $o->{fk}[0](" . join(',', @{$o->{fk}[1]}) . ')';
    }
    return $sql;
}

sub _table_ddl {
    my ($spec, $driver, $name) = @_;
    $name //= $spec->{name};
    my @defs = map { _column_ddl($_, $driver) } @{ $spec->{columns} };
    push @defs, 'PRIMARY KEY (' . join(', ', @{ $spec->{table_pk} }) . ')'
        if $spec->{table_pk};
    for my $check (@{ $spec->{checks} || [] }) {
        push @defs, "CHECK ($check)";
    }
    return "CREATE TABLE IF NOT EXISTS $name (\n    "
        . join(",\n    ", @defs) . "\n)";
}

sub _index_ddls {
    my ($spec) = @_;
    return map {
        "CREATE " . ($_->{unique} ? 'UNIQUE ' : '')
            . "INDEX IF NOT EXISTS $_->{name} ON $spec->{name} ("
            . join(', ', @{$_->{cols}}) . ')'
    } @{$spec->{indexes} || []};
}

sub _table_spec {
    my ($name) = @_;
    return $name eq 'version_history' ? $VERSION_HISTORY_TABLE : $TABLE_BY_NAME{$name};
}

# Canonical table specs in declaration order (dev/test tooling: the
# golden v0 fixture is rendered from these, minus ds_rrd and ds.deleted).
sub _all_table_specs {
    return @TABLES;
}

# Every table name a known munin schema version may declare (the
# canonical set, the audit trail, and the pre-rename legacy table).
sub known_tables {
    my @names = map { $_->{name} } @TABLES;
    push @names, 'version_history', @$LEGACY_TABLES;
    return @names;
}

# Tables the v0 acceptance check requires to exist.
sub core_tables {
    return @CORE_TABLES;
}

# CREATE TABLE + indexes for one table (used by create_schema and by
# the tool's yolo additive repair).
sub create_table {
    my ($dbh, $name) = @_;
    my $spec = _table_spec($name)
        or die "munin: no DDL known for table '$name'\n";
    my $driver = _driver($dbh);
    _do($dbh, _table_ddl($spec, $driver));
    _do($dbh, $_) for _index_ddls($spec);
    return;
}

#------------------------------------------------------------------------------
# Public schema operations
#------------------------------------------------------------------------------

# Full current DDL: every table Munin owns, with FKs, indexes and CHECK
# constraints exactly as production requires. Does NOT create
# version_history: callers record entries via record() so every write to
# the audit trail is deliberate.
sub create_schema {
    my ($dbh) = @_;
    my $driver = _driver($dbh);

    # pg-only session setting: silence DDL notices. Harmless no-op on
    # sqlite (the branch never fires).
    $dbh->do('SET LOCAL client_min_messages = error') if $driver eq 'Pg';

    for my $spec (@TABLES) {
        create_table($dbh, $spec->{name});
    }
    return;
}

# Append one audit row: (target version, epoch, comment). The current
# schema version is MAX(version) over this table. The table itself is
# created on demand -- bootstrap and the tool both record, and record()
# is the only sanctioned writer.
sub record {
    my ($dbh, $version, $comment) = @_;
    my $driver = _driver($dbh);
    _do($dbh, _table_ddl($VERSION_HISTORY_TABLE, $driver));
    _do($dbh, 'INSERT INTO version_history (version, tstp, comment) VALUES (?, ?, ?)',
        $version, time(), $comment);
    return;
}

# Cheap state probe. Returns:
#   'fresh'       -- no Munin tables at all; safe to bootstrap
#   $version      -- MAX(version) over version_history rows
#   'unversioned' -- core Munin tables exist, no version_history rows
sub detect {
    my ($dbh) = @_;
    my $tables = _table_set($dbh);
    if ($tables->{version_history}) {
        my $max = eval {
            my ($m) = $dbh->selectrow_array('SELECT MAX(version) FROM version_history');
            $m;
        };
        return $max if defined $max;
    }
    my @names = map { $_->{name} } @TABLES;
    push @names, 'version_history', @$LEGACY_TABLES;
    return 'unversioned' if grep { $tables->{$_} } @names;
    return 'fresh';
}

# Die unless the handle's schema matches what this code expects:
#   fresh        -> ok (caller bootstraps)
#   version == N -> ok
#   otherwise    -> die with a message naming detected version, expected
#                   version, the last version_history entry, database
#                   location, and the fix ("run munin-upgrade-db").
sub verify {
    my ($dbh) = @_;
    return $VERIFIED if $VERIFIED;
    my $state = detect($dbh);
    if ($state eq 'fresh') {
        return $VERIFIED = 1;
    }
    if ($state ne 'unversioned' && $state == CURRENT_SCHEMA_VERSION) {
        return $VERIFIED = 1;
    }
    die mismatch_message($dbh, $state);
}

# Test hook: verify() memoizes per process by design (migration is
# offline); tests that drive several databases through get_dbh reset the
# memo between cases.
sub reset_verify_cache {
    $VERIFIED = undef;
    return;
}

# The runtime failure message -- identical in shape from the verify()
# path and the _db_init path. On versioned databases the "last
# migration entry" line cites the newest version_history row, so the
# error report itself says what this database last went through.
sub mismatch_message {
    my ($dbh, $state) = @_;

    my $location = $dbh->{Name} // $dbh->{Database} // 'unknown';
    my $detected = $state eq 'unversioned'
        ? 'v0 (unversioned database)'
        : "v$state";
    my $last = _last_history_entry($dbh);
    my $fix = ($state ne 'unversioned' && $state > CURRENT_SCHEMA_VERSION)
        ? 'downgrade unsupported: back up the database and reinstall the matching munin version'
        : 'stop munin, run `munin-upgrade-db`, restart';

    return join("\n",
        "munin: database schema mismatch at $location",
        "  detected:  $detected",
        '  required:  v' . CURRENT_SCHEMA_VERSION,
        "  last migration entry: $last",
        "  fix:       $fix",
        'munin: refusing to continue: running against a mismatched schema',
        '       risks data corruption',
        '');
}

sub _last_history_entry {
    my ($dbh) = @_;
    my ($tstp, $version, $comment) = eval {
        $dbh->selectrow_array(
            'SELECT tstp, version, comment FROM version_history ORDER BY id DESC LIMIT 1')
    };
    return '(none)' unless defined $version;
    return "$tstp v$version " . (defined $comment ? $comment : '');
}

#------------------------------------------------------------------------------
# Introspection
#------------------------------------------------------------------------------

# Full introspection: for every Munin table actually present, the
# sorted column list AND its constraints (PK/UNIQUE/CHECK/index
# membership, FK sources and targets). Used by the tool for
# verification, the v0 acceptance check, and extra-column
# classification.
#
# Shape (both drivers, normalized):
#   { table => {
#       columns => { name => { type, notnull, dflt, pk } },
#       pk      => [ sorted pk cols ],
#       uniq    => { 'a|b' => [sorted cols] },    # UNIQUE sets (minus pk)
#       indexes => { name => { cols => [...], unique => 0|1 } },
#       checks  => [ expr, ... ],
#       fks     => { 'c->tbl(r)' => { cols, reftable, refcols } },
#   } }
sub introspect {
    my ($dbh) = @_;
    return _driver($dbh) eq 'Pg' ? _introspect_pg($dbh) : _introspect_sqlite($dbh);
}

sub _fk_key {
    my ($cols, $reftable, $refcols) = @_;
    return join(',', @$cols) . '->' . $reftable . '(' . join(',', @$refcols) . ')';
}

sub _introspect_sqlite {
    my ($dbh) = @_;
    my %present = %{ _table_set($dbh) };
    my %out;

    for my $table (sort grep { _is_munin_table($_) } keys %present) {
        my $cols_rows = $dbh->selectall_arrayref("PRAGMA table_info($table)");
        my (%columns, @pk);
        for my $r (@$cols_rows) {
            my (undef, $name, $type, $notnull, $dflt, $pk) = @$r;
            $columns{$name} = {
                type    => $type,
                notnull => $notnull + 0,
                dflt    => defined $dflt ? _norm_dflt($dflt) : undef,
                pk      => $pk + 0,
            };
            push @pk, $name if $pk;
        }
        @pk = sort @pk;

        # Indexes: origin 'c' = CREATE INDEX (named, compared), 'u'/'pk'
        # = table constraints (folded into the uniq/pk sets).
        my (%indexes, %uniq);
        my $idx_rows = $dbh->selectall_arrayref("PRAGMA index_list($table)");
        for my $r (@$idx_rows) {
            my (undef, $name, $unique, $origin) = @$r;
            # index_info rows: (seqno, cid, name); cid -1 = rowid alias
            # (no column name).
            my $icols = $dbh->selectall_arrayref("PRAGMA index_info($name)");
            my @icolnames = map { defined $_->[2] ? $_->[2] : () } @$icols;
            if ($origin && $origin eq 'c') {
                $indexes{$name} = { cols => \@icolnames, unique => $unique + 0 };
            }
            if ($unique && (!$origin || $origin ne 'pk')) {
                $uniq{ join('|', sort @icolnames) } = [ sort @icolnames ];
            }
        }
        delete $uniq{ join('|', @pk) } if @pk;

        # FKs: PRAGMA lists rows per FK id, seq DESC.
        my (%fk_by_id, %fkmap);
        my $fk_rows = $dbh->selectall_arrayref("PRAGMA foreign_key_list($table)");
        for my $r (@$fk_rows) {
            my ($id, $seq, $reftable, $from, $to) = @$r;
            push @{$fk_by_id{$id}{order}}, [ $seq, $from ];
            $fk_by_id{$id}{reftable} = $reftable;
            $fk_by_id{$id}{refcols}[$seq] = $to;
        }
        for my $id (keys %fk_by_id) {
            my @cols = map { $_->[1] }
                sort { $a->[0] <=> $b->[0] } @{$fk_by_id{$id}{order}};
            my $refcols = [ grep { defined } @{$fk_by_id{$id}{refcols}} ];
            my $key = _fk_key(\@cols, $fk_by_id{$id}{reftable}, $refcols);
            $fkmap{$key} = { cols => \@cols, reftable => $fk_by_id{$id}{reftable}, refcols => $refcols };
        }

        $out{$table} = {
            columns => \%columns,
            pk      => \@pk,
            uniq    => \%uniq,
            indexes => \%indexes,
            checks  => [ _sqlite_checks($dbh, $table) ],
            fks     => \%fkmap,
        };
    }
    return \%out;
}

# CHECK constraints live inside the CREATE TABLE text on sqlite.
sub _sqlite_checks {
    my ($dbh, $table) = @_;
    my ($sql) = $dbh->selectrow_array(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        undef, $table);
    return () unless defined $sql;
    my @checks;
    while ($sql =~ /CHECK\s*\(/gi) {
        my ($expr, $depth) = ('', 1);
        for (my $i = pos($sql); $i < length($sql) && $depth > 0; $i++) {
            my $ch = substr($sql, $i, 1);
            $depth++ if $ch eq '(';
            $depth-- if $ch eq ')';
            $expr .= $ch if $depth > 0;
        }
        push @checks, $expr;
    }
    return @checks;
}

sub _introspect_pg {
    my ($dbh) = @_;
    my %present = %{ _table_set($dbh) };
    my %out;

    for my $table (sort grep { _is_munin_table($_) } keys %present) {
        $out{$table} = {
            columns => {}, pk => [], uniq => {}, indexes => {}, checks => [], fks => {},
        };
    }

    my $sth = $dbh->prepare(
        "SELECT table_name, column_name, data_type, is_nullable, column_default
         FROM information_schema.columns WHERE table_schema = 'public'");
    $sth->execute;
    while (my $r = $sth->fetchrow_hashref) {
        next unless $out{ $r->{table_name} };
        $out{ $r->{table_name} }{columns}{ $r->{column_name} } = {
            type    => _pg_type($r->{data_type}),
            notnull => ($r->{is_nullable} || '') eq 'NO' ? 1 : 0,
            dflt    => _norm_dflt($r->{column_default}),
            pk      => 0,
        };
    }

    # Constraints: PK / UNIQUE / CHECK / FK, straight from the catalog.
    my %constraint_names;    # indexes backing constraints are not "user" indexes
    my $csth = $dbh->prepare(
        "SELECT conrelid::regclass::text AS tbl, conname, contype,
                pg_get_constraintdef(oid) AS def
         FROM pg_constraint WHERE connamespace = 'public'::regnamespace");
    $csth->execute;
    while (my $r = $csth->fetchrow_hashref) {
        my $table = $r->{tbl};
        $table =~ s/^"//; $table =~ s/"$//;
        next unless $out{$table};
        $constraint_names{$r->{conname}} = 1;
        my $def = $r->{def} // '';
        if ($r->{contype} eq 'p') {
            if ($def =~ /^PRIMARY KEY \((.+)\)\z/) {
                my @pkcols = _split_cols($1);
                $out{$table}{pk} = [ sort @pkcols ];
            }
        } elsif ($r->{contype} eq 'u') {
            if ($def =~ /^UNIQUE \((.+)\)\z/) {
                my @cols = _split_cols($1);
                @cols = sort @cols;
                $out{$table}{uniq}{ join('|', @cols) } = \@cols;
            }
        } elsif ($r->{contype} eq 'f') {
            if ($def =~ /^FOREIGN KEY \((.+)\) REFERENCES "?([\w.]+)"?\((.+)\)/) {
                my @cols     = _split_cols($1);
                my $reftable = $2;
                $reftable =~ s/^.*\.//;
                my @refcols  = _split_cols($3);
                $reftable =~ s/"//g;
                my $key = _fk_key(\@cols, $reftable, \@refcols);
                $out{$table}{fks}{$key} = { cols => \@cols, reftable => $reftable, refcols => \@refcols };
            }
        } elsif ($r->{contype} eq 'c') {
            if ($def =~ /^CHECK \((.*)\)\s*\z/s) {
                push @{ $out{$table}{checks} }, $1;
            }
        }
    }

    # Indexes: user-created only (constraint-backing indexes are folded
    # into the pk/uniq sets above).
    my $isth = $dbh->prepare(
        "SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'");
    $isth->execute;
    while (my $r = $isth->fetchrow_hashref) {
        my $table = $r->{tablename};
        next unless $out{$table};
        next if $constraint_names{ $r->{indexname} };
        my $def = $r->{indexdef} // '';
        my $unique = $def =~ /^CREATE UNIQUE / ? 1 : 0;
        my @cols = $def =~ /\((.+)\)\s*\z/s ? _split_cols($1) : ();
        $out{$table}{indexes}{ $r->{indexname} } = { cols => \@cols, unique => $unique };
        if ($unique) {
            my $key = join('|', sort @cols);
            $out{$table}{uniq}{$key} = [ sort @cols ];
        }
    }

    for my $table (keys %out) {
        my $pkset = join('|', @{ $out{$table}{pk} });
        delete $out{$table}{uniq}{$pkset} if length $pkset;
    }
    return \%out;
}

sub _split_cols {
    my ($s) = @_;
    my @out;
    for my $c (split /,/, ($s // '')) {
        $c =~ s/^\s+//;
        $c =~ s/\s+$//;
        $c =~ s/"//g;
        push @out, $c;
    }
    return @out;
}

sub _is_munin_table {
    my ($name) = @_;
    return 1 if $TABLE_BY_NAME{$name};
    return 1 if $name eq 'version_history';
    return 1 if grep { $_ eq $name } @$LEGACY_TABLES;
    return 0;
}

#------------------------------------------------------------------------------
# Expected schema + diff (fingerprint verification)
#------------------------------------------------------------------------------

# The introspection shape the current code expects, derived from the
# same canonical specs the DDL renders from.
sub expected_schema {
    my ($driver) = @_;
    $driver //= 'SQLite';
    my %out;

    for my $spec (@TABLES) {
        my (%columns, @pk, %uniq, %indexes, @checks, %fks);
        for my $col (@{ $spec->{columns} }) {
            my ($name, $type, $o) = @$col;
            $o ||= {};
            my $is_pk = $o->{pk} || $type eq 'IDPK';
            my $dflt = $o->{dflt};
            if ($type eq 'IDPK' && $driver eq 'Pg') {
                $dflt = "nextval('" . $spec->{name} . "_${name}_seq')";
            }
            $columns{$name} = {
                type    => $type eq 'IDPK' ? 'INTEGER' : $type,
                notnull => $o->{notnull} ? 1 : 0,
                dflt    => defined $dflt ? _norm_dflt($dflt) : undef,
                pk      => $is_pk ? 1 : 0,
            };
            push @pk, $name if $is_pk;
            if ($o->{unique}) {
                my $key = $name;
                $uniq{$key} = [$name];
            }
            if ($o->{fk}) {
                my $key = _fk_key([$name], $o->{fk}[0], $o->{fk}[1]);
                $fks{$key} = { cols => [$name], reftable => $o->{fk}[0], refcols => [ @{$o->{fk}[1]} ] };
            }
        }
        if ($spec->{table_pk}) {
            @pk = @{$spec->{table_pk}};
        }
        @pk = sort @pk;
        # pg implicitly makes PRIMARY KEY columns NOT NULL (sqlite does
        # not: PRAGMA reports the declared nullability).
        if ($driver eq 'Pg') {
            $columns{$_}{notnull} = 1 for grep { exists $columns{$_} } @pk;
        }
        for my $idx (@{ $spec->{indexes} || [] }) {
            $indexes{ $idx->{name} } = { cols => [ @{$idx->{cols}} ], unique => $idx->{unique} ? 1 : 0 };
            if ($idx->{unique}) {
                my $key = join('|', sort @{ $idx->{cols} });
                $uniq{$key} = [ sort @{ $idx->{cols}} ];
            }
        }
        @checks = @{ $spec->{checks} || [] };
        delete $uniq{ join('|', @pk) } if @pk;

        $out{ $spec->{name} } = {
            columns => \%columns,
            pk      => \@pk,
            uniq    => \%uniq,
            indexes => \%indexes,
            checks  => \@checks,
            fks     => \%fks,
        };
    }
    return \%out;
}

# Compare live introspection against the expected schema.
# Returns { ok => 0|1, problems => [...], warnings => [...] }.
#
# Refuse-level (problems): missing tables/columns/constraints, extra
# columns carrying any constraint, extra unique sets/indexes/checks.
# Warn-level: unconstrained extra columns, extra plain indexes, extra
# FKs -- tolerated noise, reported so the operator sees it.
sub diff_schema {
    my ($actual, $expected, $driver) = @_;
    $driver //= 'SQLite';
    my (@problems, @warnings);

    # Which columns are referenced by any constraint (PK/UNIQUE/CHECK/
    # index membership, FK sources and targets)?
    my %constrained;    # "table.col" => 1
    for my $table (keys %$actual) {
        my $a = $actual->{$table};
        $constrained{"$table.$_"} = 1 for @{ $a->{pk} };
        $constrained{"$table.$_"} = 1 for map { @$_ } values %{ $a->{uniq} };
        $constrained{"$table.$_"} = 1 for map { @{ $_->{cols} } } values %{ $a->{fks} };
        for my $expr (@{ $a->{checks} || [] }) {
            $constrained{"$table.$_"} = 1 for grep { $expr =~ /\b\Q$_\E\b/ } keys %{ $a->{columns} };
        }
    }
    for my $table (keys %$actual) {
        for my $fk (values %{ $actual->{$table}{fks} }) {
            $constrained{ "$fk->{reftable}.$_" } = 1 for @{ $fk->{refcols} };
        }
    }

    for my $table (sort keys %$expected) {
        my $e = $expected->{$table};
        unless (exists $actual->{$table}) {
            push @problems, { kind => 'missing_table', table => $table };
            next;
        }
        my $a = $actual->{$table};

        # Columns
        for my $col (sort keys %{ $e->{columns} }) {
            unless (exists $a->{columns}{$col}) {
                push @problems, { kind => 'missing_column', table => $table, col => $col };
                next;
            }
            my $want = $e->{columns}{$col};
            my $got  = $a->{columns}{$col};
            for my $attr (qw(type notnull)) {
                if (($got->{$attr} // '') ne ($want->{$attr} // '')) {
                    push @problems, {
                        kind   => 'column_mismatch',
                        table  => $table,
                        col    => $col,
                        detail => "$attr: expected $want->{$attr}, found " . ($got->{$attr} // '(none)'),
                    };
                }
            }
            if (defined $want->{dflt} && ($got->{dflt} // '') ne $want->{dflt}) {
                push @problems, {
                    kind   => 'column_mismatch',
                    table  => $table,
                    col    => $col,
                    detail => "default: expected $want->{dflt}, found " . ($got->{dflt} // '(none)'),
                };
            }
        }
        for my $col (sort keys %{ $a->{columns} }) {
            next if exists $e->{columns}{$col};
            if ($constrained{"$table.$col"}) {
                push @problems, { kind => 'constrained_extra_column', table => $table, col => $col };
            } else {
                push @warnings, { kind => 'extra_column', table => $table, col => $col };
            }
        }

        # Primary key
        my $got_pk  = join('|', @{ $a->{pk} });
        my $want_pk = join('|', @{ $e->{pk} });
        if ($got_pk ne $want_pk) {
            push @problems, { kind => 'missing_pk', table => $table, detail => "expected [$want_pk], found [$got_pk]" };
        }

        # UNIQUE sets
        for my $key (sort keys %{ $e->{uniq} }) {
            unless ($a->{uniq}{$key}) {
                push @problems, { kind => 'missing_uniq', table => $table, detail => $key };
            }
        }
        for my $key (sort keys %{ $a->{uniq} }) {
            next if $e->{uniq}{$key};
            push @problems, { kind => 'extra_uniq', table => $table, detail => $key };
        }

        # Named indexes
        for my $name (sort keys %{ $e->{indexes} }) {
            my $want = $e->{indexes}{$name};
            my $got  = $a->{indexes}{$name};
            unless ($got) {
                push @problems, { kind => 'missing_index', table => $table, detail => $name };
                next;
            }
            if (join('|', @{ $got->{cols} }) ne join('|', @{ $want->{cols} })
                || $got->{unique} != $want->{unique}) {
                push @problems, { kind => 'missing_index', table => $table, detail => "$name (shape differs)" };
            }
        }
        for my $name (sort keys %{ $a->{indexes} }) {
            next if $e->{indexes}{$name};
            if ($a->{indexes}{$name}{unique}) {
                push @problems, { kind => 'extra_unique_index', table => $table, detail => $name };
            } else {
                push @warnings, { kind => 'extra_index', table => $table, detail => $name };
            }
        }

        # CHECK constraints: exact text on sqlite; pg reformats
        # expressions ((x)::integer vs CAST(x AS INTEGER)), so there the
        # expected identifiers must merely appear in the stored one.
        my @actual_checks = @{ $a->{checks} || [] };
        for my $want (@{ $e->{checks} || [] }) {
            my $found = grep { _check_matches($want, $_, $driver) } @actual_checks;
            unless ($found) {
                push @problems, { kind => 'missing_check', table => $table, detail => $want };
            }
        }
        if ($driver ne 'Pg') {
            for my $got (@actual_checks) {
                next if grep { $_ eq $got } @{ $e->{checks} || [] };
                push @problems, { kind => 'extra_check', table => $table, detail => $got };
            }
        } else {
            # fuzzy domain: report unmatched stored checks as warnings
            for my $got (@actual_checks) {
                next if grep { _check_matches($_, $got, $driver) } @{ $e->{checks} || [] };
                push @warnings, { kind => 'extra_check', table => $table, detail => $got };
            }
        }

        # Foreign keys
        for my $key (sort keys %{ $e->{fks} }) {
            unless ($a->{fks}{$key}) {
                push @problems, { kind => 'missing_fk', table => $table, detail => $key };
            }
        }
        for my $key (sort keys %{ $a->{fks} }) {
            next if $e->{fks}{$key};
            push @warnings, { kind => 'extra_fk', table => $table, detail => $key };
        }
    }

    return {
        ok       => @problems ? 0 : 1,
        problems => \@problems,
        warnings => \@warnings,
    };
}

sub _check_matches {
    my ($want, $got, $driver) = @_;
    return ($want // '') eq ($got // '') if $driver ne 'Pg';
    my %skip = map { $_ => 1 } qw(CAST INTEGER AS NOT NULL AND OR TRUE FALSE);
    my %got_tokens = map { $_ => 1 } ($got =~ /([A-Za-z_]\w*)/g);
    for my $token ($want =~ /([A-Za-z_]\w*)/g) {
        next if $skip{$token};
        return 0 unless $got_tokens{$token};
    }
    return 1;
}

#------------------------------------------------------------------------------
# Migration: the one v0 -> v1 step
#------------------------------------------------------------------------------

# Applies, in order:
#   1. state: ADD COLUMN prev_alarm/eval_value/extinfo if missing
#   2. ds:    ADD COLUMN deleted INTEGER DEFAULT 0 if missing
#   3. ds_rrd: CREATE TABLE if missing; backfill from ds_attr
#      rrd:file/rrd:field/rrd:alias (COALESCE field '42' for
#      pre-rrd:field files); DELETE the migrated ds_attr rows
#   4. notification ledger rename (pre-rename databases carry the old
#      `notification` table; the ledger must survive, throttling state
#      included)
#   5. FK retrofit: for each Munin table whose actual DDL lacks an
#      expected REFERENCES clause, repair it
#
# Returns a list of human-readable step descriptions actually applied.
#
# opts: additive => 1 -- yolo mode. Never DELETEs data rows: the rrd:*
# ds_attr retirement is skipped (rows kept, narrated), and the pg FK
# retrofit uses NOT VALID constraints (dangling rows kept, narrated).
sub migrate_v0_to_v1 {
    my ($dbh, $opts) = @_;
    $opts ||= {};
    my $additive = $opts->{additive} ? 1 : 0;
    my $driver   = _driver($dbh);
    my @steps;

    # 1. state columns (the check-first, ALTER-second guard dance is
    # carried over from _db_init: pg has no ADD COLUMN IF EXISTS)
    my $state_cols = _column_set($dbh, 'state');
    my @missing_state = grep { !$state_cols->{$_} } qw(prev_alarm eval_value extinfo);
    if (@missing_state) {
        _do($dbh, "ALTER TABLE state ADD COLUMN $_ VARCHAR") for @missing_state;
        push @steps, 'state: added column' . (@missing_state > 1 ? 's' : '')
            . ' ' . join(', ', @missing_state);
    }

    # 2. ds.deleted soft-delete column
    my $ds_cols = _column_set($dbh, 'ds');
    unless ($ds_cols->{deleted}) {
        _do($dbh, 'ALTER TABLE ds ADD COLUMN deleted INTEGER DEFAULT 0');
        push @steps, 'ds: added column deleted';
    }

    # 3. ds_rrd: create, backfill, retire
    my $tables = _table_set($dbh);
    my $created = 0;
    unless ($tables->{ds_rrd}) {
        create_table($dbh, 'ds_rrd');
        $created = 1;
    }
    my $would = _count($dbh,
        "SELECT COUNT(*) FROM ds_attr f
         WHERE f.name = 'rrd:file'
           AND NOT EXISTS (SELECT 1 FROM ds_rrd r WHERE r.ds_id = f.id)");
    _do($dbh,
        "INSERT INTO ds_rrd (ds_id, file, field, alias)
         SELECT f.id, f.value, COALESCE(d.value, '42'), a.value
         FROM ds_attr f
         LEFT JOIN ds_attr d ON d.id = f.id AND d.name = 'rrd:field'
         LEFT JOIN ds_attr a ON a.id = f.id AND a.name = 'rrd:alias'
         WHERE f.name = 'rrd:file'
           AND NOT EXISTS (SELECT 1 FROM ds_rrd r WHERE r.ds_id = f.id)");
    my $retired = 0;
    my $kept    = 0;
    if ($additive) {
        $kept = _count($dbh,
            "SELECT COUNT(*) FROM ds_attr WHERE name IN ('rrd:file', 'rrd:field', 'rrd:alias')");
    } else {
        $retired = _count($dbh,
            "SELECT COUNT(*) FROM ds_attr WHERE name IN ('rrd:file', 'rrd:field', 'rrd:alias')");
        _do($dbh, "DELETE FROM ds_attr WHERE name IN ('rrd:file', 'rrd:field', 'rrd:alias')");
    }
    if ($created || $would || $retired || $kept) {
        my @bits;
        push @bits, 'created' if $created;
        push @bits, "$would mappings backfilled from ds_attr" if $would;
        push @bits, "$retired rrd:* attr rows retired"       if $retired;
        push @bits, "$kept legacy rrd:* attr rows kept (additive-only)" if $kept;
        push @steps, 'ds_rrd: ' . join(', ', @bits);
    }

    # 4. notification ledger rename (verbatim from the runtime code it
    # was moved out of: it moves, it does not get rewritten)
    my ($old_notif) = $driver eq 'Pg'
        ? $dbh->selectrow_array("SELECT to_regclass('notification')")
        : $dbh->selectrow_array(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='notification'");
    if ($old_notif) {
        _do($dbh, 'ALTER TABLE notification RENAME TO notification_tracking');
        _do($dbh, 'DROP INDEX IF EXISTS u_notification');
        _do($dbh,
            'CREATE UNIQUE INDEX IF NOT EXISTS u_notification_tracking ON notification_tracking (contact_id, service_id)');
        push @steps, 'notification ledger: renamed notification to notification_tracking';
    }

    # 5. FK retrofit
    push @steps, _fk_retrofit($dbh, $driver, $additive);

    return @steps;
}

# Read-only mirror of migrate_v0_to_v1's guards, for --check reporting.
sub pending_steps {
    my ($dbh) = @_;
    my $driver = _driver($dbh);
    my @pending;

    my $state_cols = _column_set($dbh, 'state');
    my @missing_state = grep { !$state_cols->{$_} } qw(prev_alarm eval_value extinfo);
    push @pending, 'state: add column' . (@missing_state > 1 ? 's' : '')
        . ' ' . join(', ', @missing_state) if @missing_state;

    push @pending, 'ds: add column deleted' unless _column_set($dbh, 'ds')->{deleted};

    my $tables = _table_set($dbh);
    my @bits;
    push @bits, 'create table' unless $tables->{ds_rrd};
    my $would = $tables->{ds_rrd} ? _count($dbh,
        "SELECT COUNT(*) FROM ds_attr f
         WHERE f.name = 'rrd:file'
           AND NOT EXISTS (SELECT 1 FROM ds_rrd r WHERE r.ds_id = f.id)") : undef;
    push @bits, "$would ds_attr rrd:* mappings backfilled" if defined $would && $would;
    push @pending, 'ds_rrd: ' . join(', ', @bits) if @bits;

    my ($old_notif) = $driver eq 'Pg'
        ? $dbh->selectrow_array("SELECT to_regclass('notification')")
        : $dbh->selectrow_array(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='notification'");
    push @pending, 'notification ledger: rename notification to notification_tracking'
        if $old_notif;

    my $actual   = introspect($dbh);
    my $expected = expected_schema($driver);
    my @missing_fk;
    for my $table (sort keys %$expected) {
        next unless $actual->{$table};
        for my $key (sort keys %{ $expected->{$table}{fks} }) {
            push @missing_fk, "$table $key" unless $actual->{$table}{fks}{$key};
        }
    }
    push @pending, 'FK retrofit: ' . join('; ', @missing_fk) if @missing_fk;

    return @pending;
}

sub _fk_retrofit {
    my ($dbh, $driver, $additive) = @_;
    my @steps;

    my $actual  = introspect($dbh);
    my $tables  = _table_set($dbh);
    my $expected = expected_schema($driver);

    for my $table (sort keys %$expected) {
        next unless $tables->{$table};
        my $have = $actual->{$table} ? $actual->{$table}{fks} : {};
        my @missing = grep { !$have->{$_} } sort keys %{ $expected->{$table}{fks} };
        next unless @missing;

        if ($driver eq 'Pg') {
            for my $key (@missing) {
                my $fk = $expected->{$table}{fks}{$key};
                my $name = $table . '_' . join('_', @{ $fk->{cols} }) . '_fkey';
                my $not_valid = $additive ? ' NOT VALID' : '';
                _do($dbh,
                    "ALTER TABLE $table ADD CONSTRAINT $name FOREIGN KEY ("
                    . join(', ', @{ $fk->{cols} })
                    . ") REFERENCES $fk->{reftable}(" . join(', ', @{ $fk->{refcols} }) . ")"
                    . $not_valid);
                push @steps,
                    "FK retrofit: added REFERENCES $fk->{reftable}(" . join(',', @{ $fk->{refcols} })
                    . ") to $table" . ($additive ? ' (NOT VALID, additive-only)' : '');
            }
        } else {
            # sqlite: rebuild the affected table with full DDL. Only
            # metadata tables are rebuilt -- small by construction; RRD
            # files are never involved. One rebuild restores every
            # missing REFERENCES clause of the table at once.
            my $rows = _sqlite_rebuild_table($dbh, $table);
            my ($first) = $expected->{$table}{fks}{ $missing[0] };
            push @steps,
                "FK retrofit: rebuilt $table ($rows rows copied, verified) to restore REFERENCES "
                . $first->{reftable} . '(' . join(',', @{ $first->{refcols} }) . ')';
        }
    }
    return @steps;
}

sub _sqlite_rebuild_table {
    my ($dbh, $table) = @_;
    my $tmp = $table . '_munin_upgrade_tmp';
    my $spec = _table_spec($table)
        or die "munin: no DDL known for table '$table'; cannot retrofit FKs\n";

    _do($dbh, "DROP TABLE IF EXISTS $tmp");
    _do($dbh, _table_ddl($spec, 'SQLite', $tmp));

    # Preserve any column the canonical DDL does not declare (additive:
    # admin columns survive the rebuild).
    my $cols = _column_set($dbh, $table);
    my %declared = map { $_->[0] => 1 } @{ $spec->{columns} };
    for my $c (sort keys %$cols) {
        next if $declared{$c};
        _do($dbh, "ALTER TABLE $tmp ADD COLUMN $c " . ($cols->{$c}{type} || 'VARCHAR'));
    }

    my @col_names = sort keys %$cols;
    my $collist = join(', ', @col_names);
    _do($dbh, "INSERT INTO $tmp ($collist) SELECT $collist FROM $table");

    my $old_n = _count($dbh, "SELECT COUNT(*) FROM $table");
    my $new_n = _count($dbh, "SELECT COUNT(*) FROM $tmp");
    die "munin: FK retrofit row count mismatch rebuilding $table ($old_n -> $new_n); refusing\n"
        unless $old_n == $new_n;

    _do($dbh, "DROP TABLE $table");
    _do($dbh, "ALTER TABLE $tmp RENAME TO $table");
    _do($dbh, $_) for _index_ddls($spec);

    return $new_n;
}

1;

__END__

=head1 NAME

Munin::Master::Schema - single source of truth for Munin's SQL schema

=head1 SYNOPSIS

 use Munin::Master::Schema;
 use Munin::Master::Schema qw(CURRENT_SCHEMA_VERSION);

 # runtime bootstrap (Update::_db_init): virgin database only
 my $state = Munin::Master::Schema::detect($dbh);
 if ($state eq 'fresh') {
     Munin::Master::Schema::create_schema($dbh);
     Munin::Master::Schema::record($dbh, CURRENT_SCHEMA_VERSION,
         'bootstrap: full schema created');
 }

 # every runtime handle: verify or die (never repair)
 Munin::Master::Schema::verify($dbh);

 # offline migration (script/munin-upgrade-db) -- the only migrator
 my @steps = Munin::Master::Schema::migrate_v0_to_v1($dbh);

=head1 DESCRIPTION

Schema evolution is offline by contract: C<get_dbh> verifies the schema
version at the single choke point and dies with an actionable message on
any mismatch; C<Update::_db_init> bootstraps a virgin database or dies;
all migration logic lives in C<script/munin-upgrade-db> and this module.

The schema version is tracked in the C<version_history> table (version,
unix epoch, human-readable comment per applied step) -- both the
current-version check (C<MAX(version)>) and an audit trail of every
migration a database has been through. It is immune to the C<param>
table churn (C<_db_params_update> deletes and reinserts all param rows
every cycle).

=head1 FUNCTIONS

=over

=item B<create_schema>

 my $dbh->...;  Munin::Master::Schema::create_schema($dbh);

Full current DDL: every table Munin owns, with FKs, indexes and CHECK
constraints exactly as production requires. Does NOT create
C<version_history>: callers record entries via C<record()>.

=item B<record>

 Munin::Master::Schema::record($dbh, $version, $comment);

Append one audit row. The current schema version is C<MAX(version)>
over this table.

=item B<detect>

 my $state = Munin::Master::Schema::detect($dbh);

Returns C<'fresh'> (no Munin tables; safe to bootstrap), the current
version number, or C<'unversioned'> (core tables exist, no
C<version_history> rows).

=item B<verify>

 Munin::Master::Schema::verify($dbh);

Dies unless the handle's schema matches what this code expects. Memoized
per process. Runtime daemons never repair, adopt or guess.

=item B<migrate_v0_to_v1>

 my @steps = Munin::Master::Schema::migrate_v0_to_v1($dbh);
 my @steps = Munin::Master::Schema::migrate_v0_to_v1($dbh, { additive => 1 });

The one v0->v1 migration step; returns human-readable descriptions of
what was actually applied. C<additive> (yolo mode) never DELETEs data
rows.

=item B<introspect> / B<expected_schema> / B<diff_schema>

Full introspection of the live schema, the schema this code expects,
and the comparison (used by the tool's fingerprint verification).

=item B<pending_steps>

Read-only mirror of C<migrate_v0_to_v1>'s guards, for C<--check>.

=item B<reset_verify_cache>

Test hook: clears the memoized verify() result.

=back

=cut
