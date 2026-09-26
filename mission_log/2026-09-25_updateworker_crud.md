# Mission Log: UpdateWorker CRUD Refactoring

**Date:** 2026-09-25
**Context:** Munin update logs showed "Use of uninitialized value $ds_id" warnings during spoolfetch. Investigation revealed a deeper architectural issue with how datasources were managed.

---

## What We Did

### Phase 1: Symptom Investigation

Started with a Perl warning at `UpdateWorker.pm` line 780:
```
Use of uninitialized value $ds_id in concatenation (.) or string
```

Initial instinct was to fix the symptom by moving the `next unless defined $ds_id` guard before the DEBUG statement. User challenged this: "do not fix the symptom, try to find WHY."

### Phase 2: Root Cause Analysis

Traced the data flow:
1. `_db_state_update()` queries for ds_id, gets NULL
2. Warning fires, function returns early
3. Data silently dropped

Key question: **Is NULL valid here?**

Answer: NULL is *handled gracefully* (early return, no crash), but the data is **lost**. That's not legitimate.

### Phase 3: Architectural Discovery

Found the root cause in `_db_service()`:

```perl
# Line 419-422: DELETE all ds_attr rows
{
    my $sth_del_attr = $dbh->prepare_cached('DELETE FROM ds_attr WHERE id IN (...)');
    $sth_del_attr->execute($service_id);
}

# Line 424-432: Then create datasources
for my $field_name (keys %$fields) {
    my $ds_id = $self->_db_ds_update(...);
}

# Line 692-720: RRD loop adds rrd:file/rrd:field attrs
```

**Bug:** Purge happened BEFORE RRD attrs were added. Even valid fields got deleted.

Additionally, dirty_config plugins (sending `field.value 12345:42` without `.label`/`.type`) created empty `%fields{field}` hashes. No attrs created -> ds deleted -> data lost.

### Phase 4: First Principles Design

User asked: "think from first principle"

Principle: **A datasource should exist if it has either attributes OR data.**

The original purge logic was too aggressive. Fixed by moving purge AFTER RRD creation loop.

### Phase 5: CRUD Refactoring

User identified the naive pattern:
```perl
# Current: DELETE all -> INSERT all
DELETE FROM service_attr WHERE id = ?;
for my $attr (keys %$service_attr) {
    INSERT INTO service_attr ...;
}
```

Proposed proper CRUD with comparison. Added security gate for SQL safety:

```perl
sub _db_diff_attrs {
    my ($self, $table, $id_col, $id, $attrs_old, $attrs_new) = @_;
    
    # Security gate: only allow known table/id_col combinations
    my %allowed = (
        'service_attr.id' => 1,
        'ds_attr.id' => 1,
    );
    die "..." unless $allowed{"$table.$id_col"};
    
    # Diff logic: INSERT new, UPDATE changed, DELETE removed
}
```

### Phase 6: Test-Driven Bug Discovery

Wrote 28 tests across two files:
- `munin_master_update_worker_crud.t` (16 tests) - Unit tests for _db_diff_attrs
- `munin_master_update_worker_dbstate.t` (12 tests) - Integration tests for plugin lifecycle

**Tests caught 2 bugs:**

1. **Stale datasources not deleted:** When a plugin removes a field, the ds and ds_attr entries remained. Added deletion loop:
   ```perl
   for my $old_field (keys %fields_old) {
       unless (exists $fields->{$old_field}) {
           # Delete stale datasource
       }
   }
   ```

2. **Variable scope error:** `$dbh` defined inside for loop but used outside in purge block. Fixed by using `$self->{dbh}` directly.

---

## What We Learned

### Technical

1. **DELETE+INSERT is a code smell.** Always diff first, then apply minimal changes. Better for performance, concurrency, and data integrity.

2. **Purge timing matters.** Cleanup operations must happen AFTER all data is written, not before. The original code purged before RRD attrs were added.

3. **Dirty_config plugins have implicit defaults.** A field with only `.value` (no `.label`, `.type`) is valid:
   - `label` defaults to field name
   - `type` defaults to GAUGE

4. **Security gates prevent SQL injection.** When building dynamic SQL from table/column names, always validate against an allowlist.

5. **SQLite `last_insert_id()` quirks.** The function signature varies; in mocks, ensure proper binding.

### Process

1. **Challenge "graceful handling".** The warning was suppressed, but data was lost. "Handled" != "Correct".

2. **First principles thinking.** Instead of "how do we fix this", ask "what should the correct behavior be?"

3. **Test from first principles.** Write tests that verify DB end state, not just function return values. The 12 integration scenarios caught real bugs.

4. **User's "catch 1-2 bugs" expectation.** Writing tests expecting bugs to exist forces deeper scrutiny.

---

## What We Decided

1. **Use proper CRUD with comparison** for all attribute updates (service_attr, ds_attr).

2. **Security gate pattern** for dynamic SQL: validate table/column names against allowlist.

3. **Move purge AFTER all writes.** Never cleanup before data is fully written.

4. **Delete stale datasources** in `_db_service`, not just in purge logic.

---

## Rules Added

- **CRUD over DELETE+INSERT:** When updating key-value attrs, diff old vs new and apply minimal changes. Never bulk-delete then bulk-insert.

- **Purge-after-write:** Any cleanup/deletion logic must execute AFTER all data is written, not before.

- **Security gate for dynamic SQL:** When table/column names are interpolated into SQL, validate against an explicit allowlist first.

- **Test DB end state:** Integration tests should verify final database state, not just function return values.

---

## What We'd Do Differently

1. **Start with tests.** Writing the dbstate tests earlier would have caught the stale-ds bug immediately.

2. **Question "graceful handling" earlier.** The warning was a symptom; the data loss was the real issue.

3. **Consider service_categories.** It has composite PK `(id, category)` supporting multiple categories per service. Current code only handles one. Left for future work.

---

## Files Changed

| File | Purpose |
|------|---------|
| `lib/Munin/Master/UpdateWorker.pm` | CRUD refactoring, stale ds deletion, purge timing fix |
| `t/munin_master_update_worker_crud.t` | New: 16 unit tests for _db_diff_attrs and _db_ds_update |
| `t/munin_master_update_worker_dbstate.t` | New: 12 integration tests for plugin lifecycle scenarios |

---

## Test Results

```
t/munin_master_update_worker_crud.t ..... ok (16 tests)
t/munin_master_update_worker_dbstate.t .. ok (12 tests)
t/munin_master_update_worker.t .......... ok (30 tests, existing)
```

All 58 tests pass. No regressions.

---

## Session 2: Integration Testing and Bug Fixes (2026-09-25)

### What We Did

Ran full test suite in Docker (matching CI environment). Found and fixed 3 additional bugs:

#### Bug 3: Variable shadowing of %fields_old

**Symptom:** `UNIQUE constraint failed: ds_attr.id, ds_attr.name` on second update run.

**Root cause:** Inner `my %fields_old` inside a block shadowed the outer declaration:
```perl
my (%service_attrs_old, %fields_old);  # Line 367 - outer
{
    my %fields_old;  # Line 381 - INNER shadows outer!
    while (...) { $fields_old{...} = ...; }  # Writes to inner
}
# Inner %fields_old is gone!
```

**Fix:** Remove the inner `my` declaration.

#### Bug 4: Non-numeric input warning in to_sec

**Symptom:** `Argument "abc" isn't numeric in int at UpdateWorker.pm line 1069`

**Root cause:** `graph_data_size` parsing used `m/(\w+) for (\w+)/` which captures any word chars. When invalid input reaches `to_sec`, `int "abc"` warns.

**Fix:**
1. Tighten regex to `m/(\d+[smhdwty]?) for (\d+[smhdwty]?)/i`
2. Add guard in `to_sec`: `return 0 unless $target =~ /^\d+$/;`

#### Bug 5: Test include path

**Symptom:** Tests failed with `Can't locate Munin::Master::UpdateWorker.pm`

**Root cause:** Tests used `use lib qw(t/lib)` but modules are in `lib/`.

**Fix:** Changed all tests to `use lib qw(lib t/lib)`.

### What We Learned

#### Technical

1. **Variable shadowing is silent in Perl.** No warning unless `use warnings` is in effect AND the variable is used. Always check for inner `my` declarations that match outer variables.

2. **Docker testing matches CI.** Always verify with `make docker-test` to catch environment-specific issues.

3. **Regex specificity matters.** `\w+` is too broad for time specs - use `\d+[smhdwty]?` to match expected format.

#### Process

1. **Run integration tests early.** Unit tests passed but integration tests caught the shadowing bug.

2. **CI environment matters.** The Docker container has different paths and dependencies than local.

### What We Decided

1. **Always run `make docker-test` before committing.** Local tests may pass but CI may fail.

2. **Defensive input validation.** Add guards in utility functions like `to_sec` even if callers should validate.

### Files Changed

| File | Purpose |
|------|---------|
| `lib/Munin/Master/UpdateWorker.pm` | Fix variable shadowing, add input validation |
| `t/munin_*.t` (17 files) | Fix test include paths |
| `.github/workflows/build-n-test.yml` | No changes (reference only) |

### Test Results

```
# Docker test suite (matching CI)
All tests successful.
Files=21, Tests=392, 402 wallclock secs
Result: PASS
```

---

## Session 3: Remove Mock Code (2026-09-25)

### What We Did

Removed duplicated mock code from test files. Mocks were copying production code verbatim, which is dangerous because:

1. If real code changes, mocks might not be updated
2. Gives false confidence that real code works
3. Maintenance burden

#### Changes

- `t/munin_master_update_worker_dbstate.t`: Removed MockWorker, now uses real `Munin::Master::UpdateWorker` with blessed `{ dbh, node_id }`
- `t/munin_master_update_worker_crud.t`: Removed TestWorker, same approach

Also fixed uninitialized warning when `graph_order` is not set:
```perl
# Before
my @graph_order = split(/ /, $service_attr->{graph_order});
# After  
my @graph_order = split(/ /, $service_attr->{graph_order} // '');
```

### What We Learned

#### Technical

1. **Minimal blessed objects work for testing.** Methods like `_db_diff_attrs` only need `$self->{dbh}` and `$self->{node_id}`. No need to mock the entire object.

2. **Mock code rots.** Identical code in two places will diverge over time. Always prefer testing real code.

3. **Coverage now works.** Lines 418-421 (stale ds deletion) are now covered by real tests.

#### Process

1. **Audit tests for mock duplication.** Check `grep -l "package Mock" t/*.t` periodically.

2. **Legitimate mocks vs code duplication.** `Mock::Config` in `munin_common_config.t` is fine - it's a minimal subclass, not copying logic.

### What We Decided

1. **No mock code that duplicates production.** Tests must exercise real methods.

2. **Blessed hashes for simple testing.** When methods only need a few fields, `bless { dbh => $dbh, node_id => 1 }, 'Real::Package'` is sufficient.

### Test Results

```
All 38 UpdateWorker tests pass (16 + 12 + 10)
No mock code remains in test suite
```

---

## Session 4: Fix Original Bug - dirty_config Datasource Creation (2026-09-25)

### What We Did

Fixed the original bug that started this investigation: `ds_id is NULL` warnings during spoolfetch.

#### Root Cause

When a plugin sends only `field.value TIMESTAMP:42` (dirty_config) without config lines like `field.label`, the field wasn't added to `%fields`:

```perl
# Handle dirty_config
if ($arg2 && $arg2 eq "value") {
    push @fetch_data, $line;
    next; # Handled  <-- SKIPS adding to %fields!
}
```

Since `%fields` was empty, `_db_service` never created any datasources. When `uw_handle_fetch` called `_db_state_update`, it couldn't find the ds.

#### Fix

Add dirty_config fields to `%fields` with empty attrs:

```perl
if ($arg2 && $arg2 eq "value") {
    # Ensure field exists in %fields so datasource gets created
    if (!exists($fields{$arg1})) {
        push @field_order, $arg1;
        $fields{$arg1} = {};  # empty attrs, will get defaults
    }
    push @fetch_data, $line;
    next; # Handled
}
```

The empty `{}` is correct because:
- The `.value` line is **data**, not config
- It shouldn't create ds_attr entries like `label`, `type`, etc.
- The ds just needs to exist so `_db_state_update` can find it
- RRD loop will add `rrd:file` and `rrd:field` attrs, so ds survives purge

Also added explicit timestamps to spoolfetch test data to exercise `set_spoolfetch_timestamp` path.

### What We Learned

#### Technical

1. **dirty_config vs config separation.** Config lines (`.label`, `.type`) define the ds structure. Data lines (`.value`) are stored in state/RRD. Both need the ds to exist, but only config lines should create ds_attr entries.

2. **First principles tracing.** When `ds_id is NULL`, trace backwards: `_db_state_update` looks for ds → `_db_service` should have created it → `%fields` must have the field → parser must have added it.

3. **Test data matters.** The original test node sent `field1.value 42` without timestamp, which didn't exercise `set_spoolfetch_timestamp`. Changed to `field1.value TIMESTAMP:42`.

#### Process

1. **Original bug was architectural.** The CRUD refactoring exposed this bug by making the code paths more visible.

2. **Test coverage reveals design issues.** Uncovered `set_spoolfetch_timestamp` not being tested, which led to discovering the dirty_config datasource creation bug.

### What We Decided

1. **dirty_config fields must be in %fields.** Even if attrs are empty, the field needs to exist so the ds gets created.

2. **Empty attrs are valid.** A field with no config attrs (only data) is legitimate - it gets defaults and RRD attrs from the RRD loop.

### Files Changed

| File | Purpose |
|------|---------|
| `lib/Munin/Master/UpdateWorker.pm` | Add dirty_config fields to %fields |
| `t/lib/node_test_spool.pl` | Add explicit timestamps to spool data |

### Test Results

```
# Full Docker test suite
All tests successful.
Files=21, Tests=392, 400 wallclock secs
Result: PASS
```

---

## Next Steps

1. **service_categories CRUD.** Currently uses DELETE+INSERT. Should diff properly.

2. **Performance benchmark.** Compare old vs new approach with large configs.

3. **Stress test.** Verify concurrency behavior with multiple update workers.

4. **Review other DELETE+INSERT patterns** in the codebase.

5. **Audit variable shadowing.** Check for other inner `my` declarations that shadow outer variables.
