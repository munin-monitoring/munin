# Mission Log: DB-Driven Groups Implementation

**Date:** 2026-09-30
**Context:** Implementing spec `01_DB_DRIVEN_GROUPS.md` to move Munin config from in-memory tree to SQLite-first architecture. Goal: parse config once, store in DB, query at runtime.

---

## What We Did

### Phase 1: Store host connection info

Added `_db_groups_update()` to `Update.pm` that walks the config tree and stores:
- Groups in `grp` table (with parent linkage)
- Hosts in `node` table (with full path)
- Host attributes in `node_attr` table (address, port, update, update_priority)

Key bug: Initially checked `ref $group eq 'HASH'` but config tree contains blessed `M::M::Group` objects. Fixed to `ref $group` (truthy for both).

### Phase 2: Load hosts from DB

Changed `_create_workers()` to use `get_hosts()` instead of `get_all_hosts()`. Removed `group_repository` from constructor.

Key issue: `UpdateWorker` expects `$host->get_full_path()` method. Solved by:
1. Creating Host objects from DB data
2. Storing `_db_path` attribute
3. Modifying `Host::get_full_path()` to use stored path when available

### Phase 3: Store config overrides

Added `config_override` table: `(host_name, service_name, field_name, name, value)`.

Key insight: Config tree stores service attributes flattened (e.g., `cpu.user.warning` as a key in host hash), not as nested objects. Updated import logic to parse these flattened keys.

Added `get_override()` with cascade lookup: field -> service -> host level.

### Phase 4: Delete dead code

- Removed `get_groups_and_hosts()`, `get_all_hosts()` from Config.pm
- Removed GroupRepository inheritance from Group.pm
- Deleted `GroupRepository.pm`

### Cleanup: Remove ConfigDB.pm

ConfigDB.pm was an earlier attempt at DB storage that never got wired into production. Had:
- Different schema (`config`, `config_hierarchy`, `config_host`)
- OO API (`$self->dbh`)
- Only used by tests

Deleted ConfigDB.pm and its tests. Removed `import_to_db()` from ConfigParser.pm.

---

## What We Learned

### Technical

1. **Config tree structure is flattened** -- Service/field attributes stored as `service.field.attr` keys directly in host hash, not nested objects. This is from `Config.pm`'s `_concat_config_line()` logic.

2. **Blessed objects vs hashes** -- `ref $group eq 'HASH'` fails for blessed objects. Use `ref $group` (truthy for any ref) or `$group->isa('HASH')` if you need to be specific.

3. **Host::get_full_path() assumes hierarchy** -- Walks up `$self->{group}` chain. When loading from DB, we don't have that hierarchy. Solution: store path in `_db_path` and check for it first.

4. **Two overlapping implementations** -- ConfigDB.pm and Update.pm both had DB code with different schemas. ConfigDB was never used in production. Always wire new code before building alternatives.

### Process

1. **Commit often for bisect** -- User's rule. Made it easy to revert Phase 3 when import logic was wrong.

2. **Test with temp DBs** -- `tempfile(CLEANUP => 1)` gives each test its own DB that auto-deletes. No need for `clear()` functions in production code.

3. **Debug with Data::Dumper** -- When import wasn't working, printed the config tree structure to see the flattened keys. Always inspect before assuming structure.

---

## What We Decided

1. **Procedural API for DB functions** -- `get_param()`, `get_hosts()`, `get_override()` are package functions, not methods. Simpler, no OO overhead for what's essentially global state.

2. **All DB writes in Update.pm** -- Graph/HTML/Limits only need read access. This separation makes the write path clear.

3. **ConfigDB.pm deleted** -- Was test-only, never wired in. Merge useful parts later if needed, but start clean.

4. **Keep ConfigParser.pm** -- Parser is useful separate from storage. Just removed the `import_to_db()` that depended on ConfigDB.

5. **Singleton discussion** -- User questioned why Config uses singleton pattern. Consensus: move toward procedural, read from DB directly. Not done yet, but direction is clear.

---

## Rules Added

- **Commit often for bisect** -- Make small, reversible commits during implementation
- **Temp DBs for testing** -- Use `tempfile(CLEANUP => 1)`, no cleanup functions needed
- **Debug config tree** -- Use `Data::Dumper` to inspect structure before writing import logic

---

## What We'd Do Differently

1. **Wire code before building alternatives** -- ConfigDB.pm was an earlier attempt that got orphaned. Should have integrated into Update.pm from the start.

2. **Understand config tree structure earlier** -- Spent time writing import logic assuming nested structure, then had to rewrite for flattened keys. Should have inspected with Dumper first.

3. **Clean up module responsibilities earlier** -- Put `get_param()` in Update.pm initially, then realized it belongs in Config/ConfigDB. Could have thought about module boundaries first.

---

## Files Changed

| File | Purpose |
|------|---------|
| `lib/Munin/Master/Update.pm` | Added `_db_groups_update`, `get_hosts`, `get_override`, `_db_import_config` |
| `lib/Munin/Master/Host.pm` | `get_full_path` uses stored `_db_path` when available |
| `lib/Munin/Master/Config.pm` | Removed `get_groups_and_hosts`, `get_all_hosts` |
| `lib/Munin/Master/Group.pm` | Removed GroupRepository inheritance |
| `lib/Munin/Master/GroupRepository.pm` | Deleted |
| `lib/Munin/Master/ConfigDB.pm` | Deleted |
| `lib/Munin/Master/ConfigParser.pm` | Removed `import_to_db` |
| `t/munin_master_update_groups.t` | Tests for DB import and retrieval |
| `t/munin_master_configdb.t` | Deleted |
| `t/munin_master_configparser.t` | Removed ConfigDB test |

---

## Test Results

All tests pass:
```
t/munin_master_update_groups.t   -- 5 subtests, all pass
t/munin_master_config.t          -- 13 subtests, all pass
t/munin_master_configparser.t    -- 9 subtests, all pass
```

---

## Next Steps

1. **Move DB functions to ConfigDB.pm** -- User suggested splitting again later. Keep in Update.pm for now.

2. **Update HTML.pm, Limits.pm** -- Remove Config singleton dependency, use `get_dbh("readonly")` instead.

3. **Use get_override() in UpdateWorker** -- Apply config overrides during fetch, completing the "Resolution: synchronous during fetch" pattern.

4. **Remove $config from Update.pm** -- Replace module-level `my $config = Config->instance()->{config}` with `get_param()` calls.

5. **Consider module responsibilities** -- Config: parsing. ConfigDB: storage. Update: orchestration. HTML/Limits: read-only queries.
