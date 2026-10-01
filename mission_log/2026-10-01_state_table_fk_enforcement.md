# Mission Log: State Table FK Refactor + FK Enforcement

**Date:** 2026-10-01
**Context:** Picking up the "review other polymorphic tables" thread from the
URL FK schema log. The `state (id, type)` table was the last polymorphic
reference in the schema. Mid-session this grew into enabling actual FK
enforcement (`PRAGMA foreign_keys=ON`), which turned out to be the bigger job.

---

## What We Did

### Part 1: url.id is Dead Weight

Before touching `state`, a side question: does `url` need
`id INTEGER PRIMARY KEY AUTOINCREMENT`, or can `path` be the key?

Evidence: after the FK refactor, every join goes through
`u.grp_id = g.id` / `u.node_id = n.id` / `u.service_id = s.id`, every lookup
is `WHERE path = ?`, and `_db_url()` only ever does
`INSERT INTO url (path, $col)` / `UPDATE url SET path = ? WHERE $col = ?`.
Nothing selects or joins `url.id`. The single `ORDER BY id` was in
`t/munin_master_spec.t` and only counted rows anyway (sort dropped entirely).

Changed to `path VARCHAR PRIMARY KEY` in both `Update.pm` `_db_init()` and
`t/lib/SampleDB.pm`. SQLite keeps it a rowid table with a unique index on
path -- same lookup performance, one column less, no AUTOINCREMENT bookkeeping.

**Stragglers found:** the original url FK refactor (commit `bd76877fa`)
updated outer joins but missed two inner subquery joins in `HTML.pm` that
still used the old polymorphic form:

```sql
-- old (broken since bd76877fa):
INNER JOIN url u_s ON s.id = u_s.id AND u_s.type = 'service'
INNER JOIN url u_n ON u_n.id = s.node_id AND u_n.type = 'node'
-- new:
INNER JOIN url u_s ON u_s.service_id = s.id
INNER JOIN url u_n ON u_n.node_id = s.node_id
```

The original refactor grepped `u.id` and missed the `u_s`/`u_n` aliases.

### Part 2: state Table Schema

Design questions asked up front:

1. **Schema:** mirror url (`ds_id + node_id + CHECK`) or minimal (`ds_id`
   only)? Chosen: **ds_id + node_id + CHECK** -- preserves the documented
   "whole node states" intent; node states later become pure code.
2. **Pragma:** enable `PRAGMA foreign_keys = ON` now? Chosen: **yes, plus a
   first-principles test**.

All production usage was `type = 'ds'` with `id = ds.id`:
`UpdateWorker::_db_state_update` (update-then-insert), `Limits.pm` (4
queries), plus test fixtures. New schema in `_db_init()`:

```sql
CREATE TABLE state (
    ds_id INTEGER REFERENCES ds(id),
    node_id INTEGER REFERENCES node(id),
    last_epoch INTEGER, last_value VARCHAR,
    prev_epoch INTEGER, prev_value VARCHAR,
    alarm VARCHAR, num_unknowns INTEGER DEFAULT 0,
    CHECK ((ds_id IS NOT NULL) + (node_id IS NOT NULL) = 1)
);
CREATE UNIQUE INDEX pk_state_ds ON state (ds_id);
CREATE UNIQUE INDEX pk_state_node ON state (node_id);
```

Updated: `UpdateWorker.pm`, `Limits.pm`, `SampleDB.pm`, and the three test
files (`spec`, `lifecycle`, `limits`) via bulk sed.

### Part 3: FK Risk Analysis (the real work)

Enabling the pragma turns every FK violation into a hard error, so every
delete path was audited first:

1. **`_db_groups_update()` runs every cycle** (~5 min). It wipes
   `node_attr`, `node`, `url`, `grp` and re-imports from the config tree.
   `service.node_id` references node rows that are NOT wiped -- the code
   relies on **id-churn stability**: full wipe + same import order recreates
   identical ids each cycle, so surviving services/ds/state keep matching.
   With FK on, cycle 2+ dies.
2. **`notification` is keyed by `contact_id`**, and `_db_import_config()`
   wipes `contact` every cycle -- contact ids churn, so notification
   tracking already resets every cycle today (latent bug, see Next Steps).
3. **Stale ds deletion** (`_db_service`) deleted only `ds` while
   `state`/`override`/`ds_attr` children referenced it (ds_attr rows also
   leaked for stale fields).
4. **Attr-less ds purge** deleted ds whose state/override rows could exist.

### Part 4: FK-Safe Ordering

Children before parents, no cascade (same policy as the url refactor):

- Stale ds: `state` -> `override` -> `ds_attr` -> `ds` (also fixes the
  ds_attr leak for stale fields).
- Attr-less purge: `state`/`override` for attr-less ds first, then ds.
- `_db_import_config`: `notification` before `contact_attr`/`contact`.
- `_db_groups_update`: its own connection runs `PRAGMA foreign_keys=OFF`
  (documented exemption -- the wipe-and-reimport id-churn hack needs a real
  fix, not a pragma toggle; and PRAGMA is a no-op inside a transaction, so
  this connection flips AutoCommit around it).

### Part 5: Pragma + First-Principles Test

`get_dbh()` now sets `PRAGMA foreign_keys=ON` for SQLite -- placed before
the `AutoCommit = 0` switch, because PRAGMA is a no-op inside a transaction
and DBI starts one as soon as AutoCommit drops.

`t/munin_master_fk_enforcement.t` (12 tests) exercises the REAL `get_dbh` +
`_db_init`, builds a valid `grp -> node -> service -> ds` chain, then proves
from first principles:

- orphan `state.ds_id` -> rejected, FOREIGN KEY error
- both state FKs NULL -> rejected, CHECK error
- valid state row -> accepted
- orphan `url.grp_id` -> rejected
- deleting a referenced node -> rejected
- deleting a ds with state rows -> rejected
- children-first delete order -> succeeds

### Part 6: Fixture Fallout

Full suite failed: `munin_master_update_worker_dbstate.t` died with
"no such table: state" -- its hand-rolled fixture schema lacked `state` and
`override`. Fixed; also updated stale fixture schemas found along the way
(dbstate url table still had old `id/type` form, crud state table still had
`PRIMARY KEY (id, type)`). Both had been passing green while silently
exercising nothing.

---

## What We Learned

### Technical

1. **SQLite FKs are off by default.** The url table's FK columns were
   decorative for an entire session of work. `PRAGMA foreign_keys=ON` is
   required per connection, or "referential integrity" is a comment.
2. **PRAGMA foreign_keys is a no-op inside a transaction.** With
   `AutoCommit = 0` (the project default), DBI wraps the first statement in
   BEGIN -- the pragma must run while the connection is still in AutoCommit
   mode, i.e. right after connect.
3. **Id-churn stability is a real (fragile) pattern.** Full wipe + same
   import order accidentally keeps autoincrement ids stable across cycles,
   which masked the service->node dependency for years. FK enforcement
   exposed it in one review.
4. **sed gotchas produce partial replacements.** Under `-E`, literal `(`
   and `?` must be escaped (`\(`, `\?`) or they parse as grouping/quantifier.
   The `VALUES (?, 'ds', ...)` rule failed silently while the column-list
   rule in the same script succeeded -- the straggler grep then found
   nothing because `type` was gone from the columns but the `'ds'` literal
   survived in VALUES. **Spot-check the diff after bulk sed edits.**
5. **Greps must follow aliases.** The url refactor's `u.id` grep missed
   `u_s.id`/`u_n.id`. Grep for the alias pattern (`u_s\.`, `u_n\.`), not
   just the base name.
6. **Test fixture schemas drift.** Hand-copied DDL in tests stayed green
   while referencing columns production no longer had. Fixtures exercising
   production code must mirror production DDL.

### Process

1. **Audit delete paths before enabling constraints.** The pragma review
   surfaced the id-churn architecture issue that no test would have caught.
2. **First-principles tests for invariants.** The FK test tries the actual
   bad statements and asserts the actual errors -- not that "code exists".
3. **Side questions pay off.** "Do we need url.id?" removed a column AND
   found two latent bugs in one pass.
4. **Commit-often kept the phases bisectable:** url PK, state schema,
   FK-safe ordering, pragma -- each independently revertable.

---

## What We Decided

1. **state: `ds_id + node_id + CHECK`** -- mirrors url, keeps node-state
   intent, no surrogate id (the FK *is* the identity, unique-indexed).
2. **url: `path` is the PRIMARY KEY** -- it was always the identity; the
   AUTOINCREMENT id referenced nothing.
3. **Pragma ON for all `get_dbh` connections**, with one documented
   exemption: `_db_groups_update`'s connection (legacy wipe-and-reimport).
4. **No cascade anywhere** -- children deleted explicitly before parents,
   error if referenced. Consistent with the url refactor decision.
5. **notification wiped before contacts** -- behavior-neutral (contact id
   churn already reset tracking every cycle), FK-safe.

---

## Rules Added

- **Enable `PRAGMA foreign_keys=ON`** for SQLite connections; without it FK
  columns are decorative.
- **Spot-check diffs after bulk sed edits** -- quantifier/paren gotchas make
  straggler greps lie.
- **Fixture schemas mirror production DDL** -- stale fixtures pass green
  while silently testing nothing.
- **Grep for aliases, not just names** -- `u_s\.` when checking `u.id`
  usage.

---

## What We'd Do Differently

1. **Check fixture schemas first** when changing production schema -- the
   dbstate failure was avoidable with one grep.
2. **The original url FK refactor should have grepped aliased tables** --
   two broken queries shipped because the grep pattern was too narrow.
3. **Enable the pragma the same session as any FK schema work** -- one full
   session of url FK work was invisible to enforcement; the sooner
   constraints are real, the sooner they teach you about your schema.
4. **Diff-based upsert import should replace the id-churn hack soon** -- the
   FK-off exemption is honest but it is still an exemption.

---

## Files Changed

| File | Purpose |
|------|---------|
| `lib/Munin/Master/Update.pm` | state schema (FK cols + CHECK), url path-PK schema, get_dbh pragma, FK-off import exemption, notification-first contact clear |
| `lib/Munin/Master/UpdateWorker.pm` | `_db_state_update` uses ds_id, children-first stale ds delete + purge |
| `lib/Munin/Master/Limits.pm` | 4 state queries drop `type = 'ds'` |
| `lib/Munin/Master/HTML.pm` | 2 old-schema straggler joins fixed (`u_s`, `u_n`) |
| `t/lib/SampleDB.pm` | url path-PK + state FK schema, state insert |
| `t/munin_master_fk_enforcement.t` | New: 12 first-principles FK/CHECK enforcement tests |
| `t/munin_master_update_worker_dbstate.t` | Fixture gains state/override tables, url schema updated |
| `t/munin_master_update_worker_crud.t` | Fixture state schema updated |
| `t/munin_master_spec.t` | url ORDER BY dropped, state queries updated |
| `t/munin_master_lifecycle.t` | state queries updated |
| `t/munin_master_limits.t` | state queries updated |

---

## Test Results

```
t/munin_master_fk_enforcement.t ......... ok (12 tests)
t/munin_master_update_worker_dbstate.t .. ok (13 tests)
t/munin_master_spec.t ................... ok
t/munin_master_lifecycle.t .............. ok
t/munin_master_limits.t ................. ok
docker-test ............................. PASS (33 files, 488 tests)
docker-lint ............................. PASS
```

---

## Commits

| Commit | Description |
|--------|-------------|
| `eba4f2bb7` | refactor: url table uses path as PRIMARY KEY, drop surrogate id |
| `626697b43` | refactor: state table with FK columns instead of (type, id) |
| `d2b90f0ac` | fix: FK-safe delete ordering before enabling FK enforcement |
| `63e46b7e9` | feat: enable PRAGMA foreign_keys=ON for SQLite connections |

---

## Next Steps

1. **Diff-based upsert import** in `_db_groups_update` -- replace the
   wipe-and-reimport id-churn hack with upsert by natural key
   (`grp (p_id, name)`, `node (grp_id, name)`) plus explicit deletes for
   departed hosts; removes the FK-off exemption.
2. **Notification tracking bug** -- contact id churn resets throttle state
   (`num_messages`) every cycle; key notification by contact *name* or make
   contact ids stable.
3. **Migration for existing DBs** -- `CREATE TABLE IF NOT EXISTS` won't
   alter deployed schemas; beta so deferred, but production deployments
   will need a migration script for state/url.
4. **Review remaining re-import patterns** -- `param` and `config_override`
   full re-imports are FK-clean; `override` re-import is child-safe. Fine
   as-is.
