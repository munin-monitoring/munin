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

## Next Steps

1. **service_categories CRUD.** Currently uses DELETE+INSERT. Should diff properly.

2. **Performance benchmark.** Compare old vs new approach with large configs.

3. **Stress test.** Verify concurrency behavior with multiple update workers.

4. **Review other DELETE+INSERT patterns** in the codebase.
