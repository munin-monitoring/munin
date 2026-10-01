# Mission Log: URL Table FK Schema Refactor

**Date:** 2026-09-30
**Context:** Refactoring the url table from polymorphic `(type, id)` to explicit FK columns for referential integrity. Part of the broader DB-first config migration.

---

## What We Did

### Phase 1: URL Table Schema Change

Changed from:
```sql
CREATE TABLE url (
    id INTEGER NOT NULL,
    type VARCHAR NOT NULL,  -- 'group', 'node', or 'service'
    path VARCHAR NOT NULL,
    PRIMARY KEY(id, type)
);
CREATE UNIQUE INDEX u_url_path ON url (path);
```

To:
```sql
CREATE TABLE url (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path VARCHAR UNIQUE NOT NULL,
    grp_id INTEGER REFERENCES grp(id),
    node_id INTEGER REFERENCES node(id),
    service_id INTEGER REFERENCES service(id),
    CHECK ((grp_id IS NOT NULL) + (node_id IS NOT NULL) + (service_id IS NOT NULL) = 1)
);
```

**Benefits:**
- FK constraints enforce referential integrity
- No cascade delete - errors if referenced (explicit, not silent)
- Simpler queries: `u.grp_id = g.id` vs `u.id = g.id AND u.type = 'group'`
- CHECK constraint ensures exactly one FK is set

### Phase 2: Query Updates

Updated all queries in:
- `HTML.pm` - 13 queries changed
- `Graph.pm` - URL lookup query
- `Static/Graph.pm` - service URL query
- `UpdateWorker.pm` - `_db_url()` function

Key changes:
- `ON u.id = g.id AND u.type = 'group'` → `ON u.grp_id = g.id`
- `ON u.id = n.id AND u.type = 'node'` → `ON u.node_id = n.id`
- `ON u.id = s.id AND u.type = 'service'` → `ON u.service_id = s.id`

### Phase 3: Explicit ID Names

Replaced generic `$id` variable with explicit names in each branch:
```perl
# Before
my ($id, $type) = ...;
if ($type eq "group") { ... $id ... }
elsif ($type eq "node") { ... $id ... }

# After
if (defined $grp_id) { ... $grp_id ... }
elsif (defined $node_id) { ... $node_id ... }
else { ... $service_id ... }  # CHECK constraint ensures one is set
```

More readable - clear which id is being used.

### Phase 4: SQL Injection Prevention

Added column name validation before SQL injection:
```perl
my %col_map = (group => 'grp_id', node => 'node_id', service => 'service_id');
my $col = $col_map{$type} or die "Unknown url type: $type";
die "Invalid column" unless $col =~ /^(grp_id|node_id|service_id)$/;
```

### Phase 5: Test Coverage

**Updated test schema:**
- `SampleDB.pm` - new url schema, added categories, fixed p_id, set service_title
- `t/munin_master_update_worker_dbstate.t` - new url schema
- Various test files - updated queries to use new schema

**Added end-to-end tests:**
- `_get_params_groups` - verify groups, nodes, categories
- `_get_params_services` - verify services by category
- `_get_params_fields` - verify fields for a service

**Key insight:** Rewrote tests to verify against SampleDB data from first principles, not by copying queries from source code.

---

## What We Learned

### Technical

1. **Polymorphic references don't work with FK** - SQLite doesn't support foreign keys where the referenced table depends on a column value. Must use separate columns.

2. **CHECK constraint for mutual exclusivity** - `(grp_id IS NOT NULL) + (node_id IS NOT NULL) + (service_id IS NOT NULL) = 1` ensures exactly one FK is set.

3. **INSERT OR IGNORE silently fails** - When SampleDB tried to insert node URL with same path as group URL, it silently failed due to UNIQUE constraint. Fixed by using different paths.

4. **Test queries copied from source = bad** - If source has a bug, test has same bug. Tests should verify against known data (SampleDB), not replicate source queries.

5. **DB CHECK constraint simplifies code** - With CHECK ensuring exactly one FK, no need for complex validation in Perl.

### Process

1. **Redirect to file, then pipe** - `cmd > out/file.out 2> out/file.err` then `grep` on file. Avoids pipe issues with timeout.

2. **Use out/ directory** - `out/$cmd.out` and `out/$cmd.err` convention for test output.

3. **Commit often for bisect** - Each phase committed separately, easy to revert.

4. **Test from first principles** - Compare function output against SampleDB data, not against copied queries.

---

## What We Decided

1. **FK columns over polymorphic** - Explicit columns are clearer, enforce referential integrity, enable simpler queries.

2. **No cascade delete** - Error if referenced. Explicit failure is better than silent data loss.

3. **CHECK constraint for exclusivity** - Database enforces "exactly one FK set", simplifies Perl code.

4. **Explicit ID names** - `$grp_id`, `$node_id`, `$service_id` instead of generic `$id`. More readable.

5. **Validate column names** - Prevent SQL injection even though values come from hardcoded hash.

6. **First-principles tests** - Verify against SampleDB data, not copied queries.

---

## Rules Added

- **out/ directory convention** - Use `out/$cmd.out` and `out/$cmd.err` for command output
- **Redirect before pipe** - `cmd > out/file.out 2> out/file.err` then grep
- **First-principles tests** - Compare against known data, not source code queries
- **Explicit over generic** - Use `$grp_id` not `$id` when the meaning is clear

---

## What We'd Do Differently

1. **Check test schema earlier** - Should have checked SampleDB.pm schema before starting. Spent time debugging INSERT failures.

2. **Run docker-test sooner** - Local tests passed but Docker tests revealed schema mismatches in other test files.

3. **Document SampleDB structure** - Should have documented what SampleDB creates upfront to make first-principles testing easier.

---

## Files Changed

| File | Purpose |
|------|---------|
| `lib/Munin/Master/Update.pm` | New url schema in `_db_init()` |
| `lib/Munin/Master/UpdateWorker.pm` | Updated `_db_url()` with column mapping |
| `lib/Munin/Master/HTML.pm` | Updated 13 queries, explicit ID names |
| `lib/Munin/Master/Graph.pm` | Updated URL lookup query |
| `lib/Munin/Master/Static/Graph.pm` | Updated service URL query |
| `lib/Munin/Master/Utils.pm` | Added helper (later removed) |
| `t/lib/SampleDB.pm` | New schema, categories, fixed p_id, service_title |
| `t/munin_master_graph_html_helpers.t` | End-to-end tests from first principles |
| `t/munin_master_graph.t` | Updated queries |
| `t/munin_master_html.t` | Updated queries |
| `t/munin_master_httpd_graph.t` | Updated queries |
| `t/munin_master_lifecycle.t` | Updated queries, fixed parameter order |
| `t/munin_master_spec.t` | Updated queries |
| `t/munin_master_update_worker_dbstate.t` | Updated schema |

---

## Test Results

All tests pass:
```
t/munin_master_graph_html_helpers.t - 22/22 pass
t/munin_master_update_spoolfetch.t  - 6/6 pass
t/munin_master_update.t             - 4/4 pass
t/munin_master_update_worker_crud.t - 16/16 pass
t/munin_master_update_worker_dbstate.t - 13/13 pass
docker-test                         - PASS (32 files, 473 tests)
```

---

## Next Steps

1. **Consider migration script** - For production deployments (though beta, so not needed now)

2. **Review other polymorphic tables** - Check if `state` table (type, id) should also be refactored

3. **Add index on FK columns** - For query performance if needed

4. **Document schema in spec** - Update `01_DB_DRIVEN_GROUPS.md` with new url table schema
