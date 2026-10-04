# Offline Schema Migration Tool Specification

## Overview

Schema changes to Munin's SQL database are applied by a dedicated offline
tool, `munin-upgrade-db`, invoked once during package upgrade -- never by
the running daemons. Runtime code verifies the schema version at every
database handle and dies with an actionable message on any mismatch. RRD
files remain runtime-managed: creating missing files and non-destructive
tweaks stay in the update path, unchanged by this specification.

## Motivation

`Munin::Master::Update::_db_init` currently runs on every update cycle and
quietly performs idempotent migrations inline (state-table columns,
`ds.deleted`, the `ds_rrd` backfill and `rrd:*` attribute cleanup). This
is loosely-tested migration code on the hot path, and every schema change
grows it. This session demonstrated the cost: FK violations hidden by
constraint-off test handles, a group/host import that only worked on
sqlite because of rowid churn, and pg installs that would wedge on the
second cycle.

Package upgrade is the natural moment for migration: the administrator
stops Munin, upgrades, restarts. Migration runs exactly then, with the old
code gone and the new code not yet running, and its outcome is verified
before any daemon touches data.

"Fail loudly" is the other half. A daemon limping against a mismatched
schema corrupts data silently. The correct behavior is to refuse to run,
with a message that names the problem and the fix.

## Goals

- All schema evolution between versions lives in one offline tool,
  `script/munin-upgrade-db`, tested against real old-schema fixtures.
- Runtime schema code shrinks to two operations: bootstrap a virgin
  database, and verify the version. No migration logic remains in
  `get_dbh` or `_db_init`.
- The schema version is tracked in a dedicated `version_history` table
  (version, epoch timestamp, comment per applied step) -- both the
  current-version check (`MAX(version)`) and a human-readable audit
  trail of every migration a database has been through. It is immune
  to the `param` table churn (`_db_params_update` deletes and
  reinserts all param rows every cycle).
- Every Munin master consumer (`munin-update`, `munin-limits`,
  `munin-html`, `munin-graph`, static renderers) verifies the schema at
  the single `get_dbh` choke point and fails loudly on mismatch. Today
  only `munin-update` runs `_db_init`; the others would limp.
- The tool detects incompatible databases (unrecognizable schemas,
  version stamps from a newer codebase) and refuses to touch them, with a
  diagnosis.
- RRD files remain runtime-managed: `_create_rrd_file_if_needed` and
  other non-destructive file handling in `UpdateWorker.pm` are out of
  scope and unchanged.

## Non-Goals

- No in-daemon schema migration, in any form. Migration code is removed
  from the runtime, not reorganized. The `--yolo` heuristic ladder is a
  property of `munin-upgrade-db` alone: `munin-update`, `munin-limits`,
  `munin-html` and every other runtime consumer verify and die -- they
  never repair, adopt, or guess.
- No downgrade support. A database stamped with a newer version than the
  code expects is a hard error in both runtime and tool.
- No RRD file data migration. Converting historical per-field RRDs to
  multi-DS is `munin-migrate-rrd`'s job, a separate tool.
- No packaging files in this repository (`dists/` contains only a
  README; downstream packagers own postinst wiring -- this spec documents
  the contract they must honor).
- No rolling/online migration. Munin upgrades are stop-the-world.
- No migration of foreign tables. Only tables Munin's own `_db_init`
  creates are introspected and verified; third-party tables are ignored.

## Design

### Schema versioning

One new table, created by the bootstrap path and by the tool. It is
both the version stamp and the upgrade audit trail:

```sql
CREATE TABLE IF NOT EXISTS version_history (
    id      INTEGER PRIMARY KEY,   -- SERIAL on pg
    version INTEGER NOT NULL,      -- schema version AFTER this entry
    tstp    INTEGER NOT NULL,      -- unix epoch, when the entry was written
    comment VARCHAR NOT NULL       -- what this entry did, human-readable
);
```

The current version is `MAX(version)`. One row is appended per applied
migration step (bootstrap counts as a step), so the table reads like a
changelog of the database itself: "v1 ds_rrd created, 42 mappings
backfilled from ds_attr, rrd:* attrs retired". It must not live in
`param`: `_db_params_update` runs `DELETE FROM param` and reinserts
config keys every cycle (`lib/Munin/Master/Update.pm`,
`_db_params_update`). Timestamps are unix epochs -- Munin's convention
-- kept unambiguous across sqlite and pg.

The history doubles as diagnostic input: runtime failure messages cite
the last applied entry, so "schema mismatch" reports immediately show
what this database last went through.

Version history:

| Version | Meaning |
|---------|---------|
| (none)  | Pre-versioning database ("v0"). Detected by the absence of `version_history` rows plus table introspection. |
| 1       | Current schema: full table set including `ds_rrd`, `ds.deleted`, state columns `prev_alarm`/`eval_value`/`extinfo`, FKs as declared in `Munin::Master::Schema::create_schema`. |

The current version is a constant:

```perl
package Munin::Master::Schema;
use Exporter qw(import);
our @EXPORT_OK = qw(CURRENT_SCHEMA_VERSION);

use constant CURRENT_SCHEMA_VERSION => 1;
```

### Shared schema module: Munin::Master::Schema

All DDL and introspection live in one module, used by both the runtime
bootstrap and the tool, so the two can never drift.

```perl
package Munin::Master::Schema;

# Full current DDL: every table Munin owns, with FKs, indexes and
# CHECK constraints exactly as production requires. This is the single
# source of truth -- _db_init's bootstrap and the upgrade tool both
# call it. Does NOT create version_history: callers record entries via
# record() so every write to the audit trail is deliberate.
sub create_schema {
    my ($dbh) = @_;
    ...
}

# Append one audit row: (target version, epoch, comment). The current
# schema version is MAX(version) over this table. Used by the bootstrap
# (one "full schema created" row) and by the tool (one row per applied
# migration step, comment describing what the step did).
sub record {
    my ($dbh, $version, $comment) = @_;
    $dbh->do('INSERT INTO version_history (version, tstp, comment) VALUES (?, ?, ?)',
             undef, $version, time(), $comment);
}

# Cheap state probe. Returns:
#   'fresh'          -- no Munin tables at all; safe to bootstrap
#   $version         -- MAX(version) over version_history rows
#   'unversioned'    -- core Munin tables exist, no version_history rows
sub detect {
    my ($dbh) = @_;
    ...
}

# Full introspection: for every Munin table actually present, the
# sorted column list AND its constraints (PK/UNIQUE/CHECK/index
# membership, FK sources and targets). Used by the tool for
# verification, the v0 acceptance check, and extra-column
# classification (see "Extra columns and constraints").
sub introspect {
    my ($dbh) = @_;
    ...
}

# The one v0 -> v1 migration step. Applies, in order:
#   1. state: ADD COLUMN prev_alarm/eval_value/extinfo if missing
#   2. ds:    ADD COLUMN deleted INTEGER DEFAULT 0 if missing
#   3. ds_rrd: CREATE TABLE if missing; backfill from ds_attr
#      rrd:file/rrd:field/rrd:alias (COALESCE field '42' for
#      pre-rrd:field files); DELETE the migrated ds_attr rows
#   4. FK retrofit: for each Munin table whose actual DDL lacks an
#      expected REFERENCES clause (see "FK retrofit"), repair it
# Returns a list of human-readable step descriptions actually applied.
sub migrate_v0_to_v1 {
    my ($dbh) = @_;
    ...
}

# Die unless the handle's schema matches what this code expects:
#   fresh        -> ok (caller bootstraps)
#   version == N -> ok
#   otherwise    -> die with a message naming detected version, expected
#                   version, the last version_history entry, database
#                   location, and the fix ("run munin-upgrade-db").
sub verify {
    my ($dbh) = @_;
    ...
}
```

Driver handling follows the existing handle-truth pattern from
`_db_init`: the handle decides (`$dbh->{Driver}->{Name}`), sqlite uses
`PRAGMA table_info`, pg uses `information_schema.columns`. The
ADD COLUMN guard dance (check first, then ALTER) is carried over from
the state migration currently in `_db_init` -- it moves, it does not get
rewritten.

### Runtime behavior after the change

`Munin::Master::Update::get_dbh` (the single choke point -- callers are
`Update.pm`, `Limits.pm`, `HTML.pm`, `Static/HTML.pm`, `Static/Graph.pm`,
`Graph.pm`):

```perl
sub get_dbh {
    ...connect as today (PRAGMA foreign_keys=ON, AutoCommit contract)...
    Munin::Master::Schema::verify($dbh);   # dies loudly on mismatch
    return $dbh;
}
```

`verify` is memoized per process (a global flag after the first
successful check); handles are opened repeatedly and the check is one
cheap query. There is no heuristic or repair branch anywhere in this
path -- mismatch is always fatal for a runtime process.

`Munin::Master::Update::_db_init` becomes:

```perl
sub _db_init {
    my ($self, $dbh) = @_;
    my $state = Munin::Master::Schema::detect($dbh);
    if ($state eq 'fresh') {
        Munin::Master::Schema::create_schema($dbh);
        Munin::Master::Schema::record($dbh, Munin::Master::Schema::CURRENT_SCHEMA_VERSION,
            'bootstrap: full schema created');
    } elsif ($state eq 'unversioned') {
        die _upgrade_needed_message($dbh, 'unversioned');
    } else {
        Munin::Master::Schema::verify($dbh);    # same check as get_dbh
    }
    $dbh->commit();
}
```

Removed from `_db_init`: the state-columns migration, the `ds.deleted`
migration, the `ds_rrd` create/backfill/cleanup. They exist only in
`Schema::migrate_v0_to_v1`.

The runtime failure message (both `_db_init` and `verify` paths) is
actionable and identical in shape:

```
munin: database schema mismatch at <dburl-or-path>
  detected:  v0 (unversioned database)
  required:  v1
  last migration entry: (none)
  fix:       stop munin, run `munin-upgrade-db`, restart
munin: refusing to continue: running against a mismatched schema
       risks data corruption
```

On versioned databases the `last migration entry` line cites the newest
`version_history` row (epoch, version, comment), so the error report
itself says what this database last went through.

For a newer-than-code schema the message says `downgrade unsupported:
back up the database and reinstall the matching munin version` instead
of the tool hint.

### The tool: script/munin-upgrade-db

CLI:

```
munin-upgrade-db [--check] [--dry-run] [--yolo]
  [--dbdir DIR] [--dburl URL] [--dbdriver DRIVER]
  [--dbuser USER] [--dbpasswd PASSWD]
```

Connection parameters follow the house precedence rule: **CLI arg >
config file > plugin-reported value**. Each flag overrides the
corresponding `Munin::Master::Config` setting for this invocation only;
the config file (`munin.conf`, loaded exactly as `munin-update` loads
it) overrides plugin-reported and default values. Concretely, the
database target resolves as: `--dburl` > `MUNIN_DBURL` env > config
`dburl` > (`--dbdir` or config `dbdir`) + `/datafile.sqlite`; driver,
user and password resolve the same way (`--dbdriver`/`--dbuser`/
`--dbpasswd` > config > production defaults).

| Mode | Behavior | Exit codes |
|------|----------|------------|
| `--check` | Report detected version, target version, pending steps. No writes. | 0 up-to-date, 2 upgrade needed, 1 error/incompatible |
| `--dry-run` | Print the SQL each step would execute, in order. No writes. | 0 / 1 |
| default | Run steps, verify, append `version_history` audit rows. | 0 success, 1 error/incompatible |
| `--yolo` | Tool-only escape hatch: heuristic repair ladder for databases the strict path refuses (see "YOLO mode"). Additive-only; verification still mandatory. Never available to runtime daemons. | 0 success (with audit narrative), 1 error |
| `--yolo --check` / `--yolo --dry-run` | Report/plan what the yolo ladder WOULD attempt on this database. No writes. | 0 / 1 |

Algorithm:

1. Connect, `detect`.
2. `fresh`: nothing to do (runtime bootstraps); print notice, exit 0.
3. `unversioned`: acceptance check (below). If accepted, run
   `migrate_v0_to_v1` stepwise inside a transaction, verify full
   fingerprint, then append one `version_history` row per applied step
   (comment describing what the step did) in the same transaction,
   commit. If the acceptance check fails: die with the diagnosis, touch
   nothing.
4. `version == CURRENT`: verify fingerprint, exit 0.
5. `version > CURRENT`: die, `downgrade unsupported`.
6. `version < CURRENT`: apply steps for each version boundary in order
   (only v0->v1 exists today; the stepwise structure is the point),
   appending audit rows as in step 3.
7. Every migration step is guarded by its audit row: the row is written
   in the same transaction as the step it describes, so an interrupted
   upgrade leaves `MAX(version)` at the last completed step and the
   tool can be rerun.

**v0 acceptance check.** An unversioned database is accepted only if its
core tables (`grp`, `node`, `service`, `ds`, `ds_attr`, `state`) all
exist. Anything else -- missing core tables, tables present that no
known version declares -- is "incompatible database": the tool prints the
introspection diff (found vs expected) and exits 1 without writing.
Hand-modified or foreign schemas are never guessed at -- unless the
operator explicitly asks for guessing, via `--yolo`.

### YOLO mode: heuristic repair (`--yolo`, upgrade tool only)

Strict mode's refusal is the correct default, but real databases are
sometimes ancient, hand-modified, or half-migrated by a crashed upgrade.
`--yolo` is the explicit, operator-chosen escape hatch -- and it exists
ONLY in `munin-upgrade-db`. Runtime daemons have no equivalent: their
`Schema::verify` contract is die-on-mismatch, unconditionally.

Two guarantees hold even in yolo mode:

1. **Additive-only.** Yolo mode never DROPs a table, never DROPs a
   column, and never UPDATEs or DELETEs existing data rows. (The strict
   v0->v1 step's retirement of migrated `rrd:*` ds_attr rows is skipped
   in yolo mode: the rows are kept as noted leftovers.) Table rebuilds
   for FK retrofit are the one structural exception -- they copy every
   row into the rebuilt table, verified by row counts before the drop.
2. **Verification is still mandatory.** After the ladder, the full
   fingerprint check runs exactly as in strict mode. Yolo that cannot
   make the schema verify still dies loudly (exit 1). "YOLO" means
   "guess how to get there", never "skip the arrival check" -- and it
   never means "let a running daemon guess".

The ladder, in order (first match wins):

| # | Heuristic | Action |
|---|-----------|--------|
| 1 | **Exact adoption**: introspection already matches the target schema (required tables/columns/FKs present, extras allowed) | No migration needed; append audit row `yolo: adopted pre-existing vN-shaped schema`; exit 0 |
| 2 | **Additive repair**: schema is v0-shaped or partially so, but core tables exist | CREATE missing tables (current DDL), ADD missing columns (guarded), run pending migration steps against existing data (backfills keep their `NOT EXISTS`/`COALESCE` guards), then verify |
| 3 | **Data reconciliation** (applied within 2): orphaned `ds_attr` rrd:* rows without `rrd:field` -> backfill `COALESCE '42'`; rows already present in `ds_rrd` win over backfill; unknown columns/tables in Munin tables -> keep, list in the audit comment | Never delete, always narrate |
| 4 | **Hard floor**: none of `grp`/`node`/`service`/`ds` exist | Refuse even with `--yolo`: creating an empty Munin schema over a foreign database would be a lie about what happened; exit 1 with the diagnosis |

Every applied heuristic is narrated in the `version_history` comment,
with counts, for example:

```
yolo: adopted pre-existing v0-shaped schema; created missing tables
(ds_rrd, version_history); added ds.deleted; backfilled 42 ds_rrd
mappings from ds_attr; kept 3 legacy rrd:* attr rows (additive-only);
kept 1 unknown column (service.legacy_note); FK retrofit: rebuilt
service (42 rows copied, verified) to restore REFERENCES node(id)
```

`--yolo` is documented for admins as a last resort ("restore from
backup first" is always the better answer). The postinst contract keeps
strict mode: packagers must NOT wire `--yolo` into automatic upgrades,
and no runtime path may ever call it.

**Extra columns and constraints.** Introspection classifies every column
in a Munin table beyond the declared schema, using constraint discovery
(PK/UNIQUE/CHECK/index membership, FK sources and targets):

| Extra column in a Munin table | Strict mode | YOLO mode |
|-------------------------------|-------------|-----------|
| Referenced by NO constraint (plain addition) | Warn, proceed | Warn, keep, narrate in audit comment |
| Referenced by any constraint (FK target, part of PK/UNIQUE/CHECK/index) | Refuse: incompatible (exit 1), the constraint is structural evidence the schema diverged | Refuse too: additive-only cannot drop or repair the constraint; exit 1 with the diagnosis |

The rule of thumb: unconstrained extras are tolerated noise; constrained
extras are a different schema wearing Munin's table names.

**FK retrofit.** Fresh schemas created by current `_db_init` already
declare all REFERENCES clauses; databases created by older Munin may
lack some (the schema text is what sqlite enforces). The tool compares
each Munin table's actual DDL against the expected REFERENCES set:

- sqlite: rebuild the affected table (CREATE the new one with full DDL,
  INSERT INTO new SELECT FROM old, DROP old, RENAME, recreate indexes).
  Only metadata tables are rebuilt -- small by construction; RRD files
  are never involved.
- pg: `ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY ...` (supported
  directly).

Expected REFERENCES set (from current `create_schema`):

| Table | References |
|-------|------------|
| grp | grp(id) via p_id |
| node | grp(id) via grp_id |
| node_attr | node(id) via id |
| service | node(id) via node_id |
| service_attr | service(id) via id |
| service_categories | service(id) via id |
| ds | service(id) via service_id |
| ds_attr | ds(id) via id |
| ds_rrd | ds(id) via ds_id |
| state | ds(id), node(id) |
| override | ds(id) via ds_id |
| url | grp(id), node(id), service(id) |
| notification_tracking | contact(id), service(id) |
| contact_attr | contact(id) via id |

### Build Changes

| Target | Change |
|--------|--------|
| `Build.PL` `script_files` | Add `script/munin-upgrade-db` |
| `lib/Munin/Master/Schema.pm` | New module (DDL, detect, introspect, migrate, verify) |
| `Makefile` | No new targets required; `prove` picks up the new test automatically |

### File Manifest

| File | Action | Purpose |
|------|--------|---------|
| `specs/01_OFFLINE_SCHEMA_MIGRATION.md` | Create | This spec |
| `specs/README.md` | Create | Spec index |
| `lib/Munin/Master/Schema.pm` | Create | Single source of truth: DDL, version constant, detect, introspect, v0->v1 step, verify |
| `lib/Munin/Master/Update.pm` | Modify | `get_dbh` calls `Schema::verify` (memoized); `_db_init` becomes bootstrap-or-verify; migration blocks removed |
| `script/munin-upgrade-db` | Create | Offline migration CLI (`--check`, `--dry-run`) |
| `Build.PL` | Modify | Register the new script |
| `t/munin_master_schema_migration.t` | Create | Fixture-based migration, idempotency, fail-loud cases |
| `t/lib/v0_schema.sql` | Create | Golden v0 DDL captured from pre-versioning `create_schema` (used to build upgrade fixtures) |
| `mission_log/...` | Create | Implementation log, written after the fact |

### Testing strategy

The tool's test file builds fixture databases by executing
`t/lib/v0_schema.sql` (the exact pre-versioning DDL), then:

1. **Upgrade correctness**: run the tool; compare `introspect()` output
   against a fresh bootstrap (`create_schema` on an empty db). Must be
   identical, including FK clauses (sqlite: compare `sqlite_master.sql`
   text normalized; pg: compare `information_schema` join targets).
2. **Data preservation**: seed v0 rows (`ds_attr` rrd:* rows, state
   rows, a legacy `rrd:field = "42"` mapping) before upgrading; assert
   `ds_rrd` backfill results, `ds.deleted` default, and untouched
   rows after upgrade.
2b. **Audit trail**: after upgrade, `version_history` holds one row per
   applied step, each with non-empty comment and a sane epoch; the
   bootstrap path writes its own row; `MAX(version)` equals
   CURRENT_SCHEMA_VERSION; `detect` on the upgraded fixture returns the
   version, not `unversioned`.
3. **Idempotency**: run the tool twice; second run exits 0 having done
   nothing (version current).
4. **Fail loud -- runtime**: a v0 fixture db opened through the mocked
   `get_dbh` path dies with the actionable message; a db whose history
   is stamped v99 dies with the downgrade message; a fresh db passes
   `verify`. Assert the mismatch message cites the last
   `version_history` entry.
5. **Fail loud -- tool**: a fixture with a dropped core table is refused
   with the diagnosis and left byte-identical (compare sqlite_master
   before/after).
6. **--check / --dry-run**: exit codes as specified; no writes
   (sqlite_master unchanged).
7. **YOLO ladder (tool only)**: (a) a current-shaped schema without
   history adopts with the adoption audit row; (b) a v0 fixture missing
   `ds_rrd` and `ds.deleted` repairs additively and verifies; (c) a
   fixture missing ALL core tables is refused even with `--yolo`,
   untouched; (d) the additive-only guarantee: seeded `rrd:*` ds_attr
   rows and unknown columns survive yolo mode byte-identical; (e) a yolo
   run that cannot satisfy verify still exits 1; (f) the audit comment
   lists every heuristic applied; (g) `--yolo --check` plans without
   writing. Plus: the mocked-get_dbh runtime path dies on every yolo
   fixture -- daemons never adopt or repair.
8. **Extra columns and constraints**: a fixture with an unconstrained
   extra column upgrades with a warning (and, in yolo mode, keeps it
   with a narration); a fixture with an extra column carrying a UNIQUE
   index or FK is refused in BOTH strict and yolo modes, left
   byte-identical.
9. **Connection precedence**: `--dburl`/`--dbdir` args beat the config
   file (point the args at a fixture while the config names a
   different path, assert the fixture is the one migrated); config
   beats plugin-reported/default values.
10. pg cell: the same file runs under the DBDRIVER=pg matrix cell via
   TestPG, exercising the ALTER ADD CONSTRAINT and
   information_schema paths.

Test handles built by hand (crud/dbstate use `TestUtils::dbh_rw` and
never call `get_dbh`) are unaffected: `verify` lives only in `get_dbh`.
`SampleDB`-based tests call `_db_init` on fresh databases and take the
bootstrap path, recording the bootstrap `version_history` row.

## Migration

### Phase 1: Schema module + tool (estimated 4-6h)

1. Create `lib/Munin/Master/Schema.pm`: move the full DDL from
   `_db_init` into `create_schema`; add `CURRENT_SCHEMA_VERSION`,
   `detect`, `introspect`, `migrate_v0_to_v1` (moving the three
   migration blocks from `_db_init` verbatim, plus the FK retrofit),
   `verify`.
2. Create `t/lib/v0_schema.sql` from the pre-versioning DDL (git
   history: the `create_schema` body before this change, minus
   `ds_rrd`/`deleted`/`version_history`).
3. Create `script/munin-upgrade-db` per the CLI contract, including the
   tool-only `--yolo` decision ladder.
4. Register the script in `Build.PL`.
5. Create `t/munin_master_schema_migration.t` with cases 1-7 above.
6. Run `make docker-test` -- the existing suite must stay green:
   every test database is fresh and takes the bootstrap path.

### Phase 2: Runtime slimming (estimated 1-2h)

1. Rewire `_db_init` (bootstrap-or-verify) and add the memoized
   `Schema::verify` call to `get_dbh`.
2. Delete the migration blocks from `_db_init`.
3. Run `make docker-test-matrix` (all three cells) -- green expected,
   since all test databases are fresh or mocked.

### Phase 3: Documentation (estimated 1h)

1. Postinst contract in the spec's References (snippet below) and a
   note in `doc/` if a suitable page exists.
2. Mission log entry.

Postinst contract for downstream packagers (documented, not built
here -- this repo ships no packaging):

```sh
# Debian: debian/munin-common.postinst, after unpack, before services start
if command -v munin-upgrade-db >/dev/null 2>&1; then
    munin-upgrade-db --check >/dev/null 2>&1 || munin-upgrade-db
fi
# A non-zero exit must fail the package upgrade: starting new daemons
# against an old schema is the data-corruption scenario this exists to
# prevent.
```

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Table rebuild (FK retrofit) hits a locked or huge table | Low | Med | Runs offline with Munin stopped; only metadata tables are rebuilt; tool verifies after each step and rolls back the transaction on failure |
| A production database does not match the v0 acceptance check (ancient or hand-modified) | Med | Med | Loud refusal with introspection diff; documented manual path (restore from backup, or hand-record a `version_history` row after manual repair); `--yolo` as the explicit admin escape hatch (tool only) |
| `--yolo` produces a schema that verifies but data that is subtly wrong (dangling references kept, half-migrated semantics) | Med | High | Additive-only guarantee means nothing is lost, only possibly inconsistent; the fat audit comment records every heuristic; prominent warning recommends a backup; verify failure still aborts; runtime daemons unaffected -- they verify and die regardless |
| A production DB has an admin-added constrained column/index that now refuses the upgrade | Low | Med | Refusal names the exact constraint; admin drops it (documented manual path) or repairs by hand and records a `version_history` row; unconstrained additions never trigger this |
| `verify` in `get_dbh` breaks a test that opens a hand-built schema through `get_dbh` | Low | Low | Audit shows hand-built tests use `TestUtils::dbh_rw` or mock `get_dbh` entirely; suite run in Phase 2 proves it |
| Packager does not wire the postinst, users hit the runtime die on first update | Med | Low | The die message names the exact fix; `--check` exit 2 lets monitoring detect pre-upgrade |
| Memoized verify goes stale if the schema is migrated while the process runs | Low | Low | Migration is offline by contract; processes that would observe it are stopped |
| DDL drift between `Schema::create_schema` and old reality | Low | High | `introspect`-based verification after every migration; fixture tests compare against golden v0 DDL captured from git history |

## Open Questions

- Should `--check` use exit 2 for "upgrade needed", or fold into 0/1
  for packagers that only test zero/non-zero? (Spec proposes 0/2/1;
  `|| munin-upgrade-db` in the postinst snippet works either way.)
- Should the `version_history.comment` for a step hold the full list of
  sub-actions (e.g. every backfilled mapping count), or a one-line
  summary with details left to operator logs? (Spec proposes one line
  per step, with counts where cheap: "ds_rrd: created, 42 mappings
  backfilled, 3 rrd:* attr rows retired".)
- Is `specs/` the right tracked home for this document, or should it
  live in the gitignored `plans/` working area? (Spec proposes
  `specs/`, tracked: it is a contract, not a scratch note.)

Resolved during review:

- Extra columns: warn only when NO constraint references them; any
  constrained extra column is incompatible in both modes (see "Extra
  columns and constraints").
- Connection parameters: every knob is a CLI arg; precedence is
  **CLI arg > config file > plugin-reported value**.

## References

- `mission_log/2026-10-03_multi_ds_rrd_autocreate.md` -- the session
  that surfaced the hidden-FK and id-churn problems this spec retires;
  includes the addendum on FK enforcement and the diff-based import.
- `mission_log/2026-09-24_multi_ds_rrd_migration.md` -- prior migration
  tooling (`munin-migrate-rrd`), whose offline philosophy this spec
  extends to the SQL schema.
- `plans/multi-ds-rrd.md` -- final multi-DS RRD design (runtime file
  handling that stays runtime-managed under this spec).
- Postinst contract: see Migration, Phase 3.
