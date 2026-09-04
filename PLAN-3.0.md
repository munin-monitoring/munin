# Munin 3.0 Release Plan

## Goal
Ship 3.0 with bug fixes, master-side SQL-first persistence, enhanced tests, and improved dev env. Node rewrite is separate/out-of-scope.

## Phase 1: Bug Fixes & SQL-First (commits 1-4)

### 1. Centralize `get_param()` into Update.pm
**Commit**: cherry-pick `2bb618ca`
**Files**: `lib/Munin/Master/Update.pm`, `lib/Munin/Master/Graph.pm`, `lib/Munin/Master/HTML.pm`

Adds `get_param($name, $dbh)` to Update.pm. Removes duplicated `get_param()` from Graph.pm (line 994-1003) and HTML.pm (line 860-870). Callers change to `Munin::Master::Update::get_param()`.

### 2. Harden limits/update state handling
**Commit**: cherry-pick `9f888727`
**Files**: `lib/Munin/Master/LimitsOld.pm`, `lib/Munin/Master/UpdateWorker.pm`

Fixes in LimitsOld.pm:
- Read `num_unknowns` from state table (add to SELECT)
- Add INSERT-or-UPDATE pattern for state writes
- Skip CDEF fields (graph-time virtual, no stable update-state)
- Read `type`, `extinfo`, `critical`, `warning`, `unknown_limit` from `ds_attr` instead of config hash
- Track `$new_state` and `$new_num_unknowns` properly through all branches
- **Fix the critical bug**: line 554 had `$new_state = $old_state` — alarm was never actually updated
- Initialize `$warning` as `[undef, undef]` in `get_limits_from_attrs`
- Rename `get_limits` → `get_limits_from_attrs` (reads from attrs hash, not config tree)

Fixes in UpdateWorker.pm:
- Null-guard `$ds_id` in `_db_state_update` (return early if undefined)
- Null-guard `$ds_id` in `uw_handle_fetch` (skip if undefined)
- Fix `to_sec()` case sensitivity: `lc($2)` for unit matching

### 3. Fix first-sample preservation and custom RRA
**Commit**: cherry-pick `309d1f6f`
**Files**: `lib/Munin/Master/UpdateWorker.pm`

Two 1-line fixes:
- After INSERT in `_db_state_update`, re-execute UPDATE so first sample is written (line 522)
- Use `@enlarged_resolutions` instead of `@resolutions_computer` in custom RRA loop (line 900)

### 4. Limits: project service/contact context from SQL
**Commit**: manual (ai branch had deps on other ai work)
**Files**: `lib/Munin/Master/LimitsOld.pm`

Replace config-hash lookups for `host_alias`, `graph_title`, `contacts` with SQL query joining `service`, `url`, `node`, `service_attr`, `node_attr`. Fallback to config hash if SQL returns nothing. Remove unused `$parent`, `$gparent`.

## Phase 2: Test Harness (commits 5-7)

### 5. LimitsOld unit tests
**New file**: `t/munin_master_limitsold.t`

Test the pure functions:
- `get_limits_from_attrs($attrs)` — threshold parsing: range "1:5", single "10", empty, missing
- `message_expand($hash, $text)` — template expansion: ${var:...}, ${if:...}, ${loop:...}, ${strtrunc:...}
- `validate_severities()` — severity ordering
- `get_full_group_path($group)` — path construction
- `get_notify_name($node)` — notification naming

Use `Test::More` + `Test::Exception`. Mock DBI with `Test::MockModule` for state queries.

### 6. UpdateWorker extended tests
**Extend**: `t/munin_master_update_worker.t`

Add tests for:
- `to_sec($target)` — all units: s/m/h/d/w/t/y, case sensitivity, bare integers
- `_db_state_update()` — null ds_id handling, INSERT-then-UPDATE flow
- `parse_custom_resolution()` — edge cases
- `enlarge_custom_resolution()` — output validation

### 7. CI pipeline fixes
**File**: `.github/workflows/build-n-test.yml`

- Set `TEST_CRITIC=1` to run `xt/critic.t`
- Set `TEST_DOC=1` to run `xt/plugins-munindoc.t`
- Add `make lint` step (shellcheck + codespell + whitespace)
- Add `perl -c` syntax checks for all lib/ modules

## Phase 3: Dev Environment (commits 8-11)

### 8. Document dev scripts
**New file**: `dev_scripts/README.md`

Document all 24 scripts: purpose, usage, examples. Add `--help` output to key scripts (`install`, `run`, `all`, `plugin`).

### 9. Fix dependency issues
**Files**: `cpanfile`, `Build.PL`

- Move `Test::Perl::Critic` from `requires` to `on 'test'` section
- Add `Directory::Scratch`, `Test::Exception`, `Test::MockObject::Extends` to `Build.PL` test_requires
- Fix Perl version inconsistency (5.10.0 vs 5.10.1)

### 10. Improve sandbox workflow
**File**: `dev_scripts/install`

- Add `status` command to show sandbox state
- Add `logs` command to tail all logs
- Add `reset` command (clean + rebuild)
- Reduce sleep times in integration tests

### 11. Docker dev env
**New file**: `Dockerfile.dev`

- Based on Debian bookworm
- All deps pre-installed
- Volume mount for live code editing
- `docker compose` setup with munin-node + master
- `make docker-dev` target in Makefile

## Phase 4: Release (commits 12-13)

### 12. Update ChangeLog
Generate changelog entry for 3.0 using the `Checklist` procedure.

### 13. Tag and build
- Commit changelog
- `git tag -s 3.0 -m "3.0"`
- `make tar`

## Verification
1. `prove -l t/` — run all tests
2. `prove -l xt/critic.t` — perlcritic
3. `make lint` — shellcheck + codespell
4. `perl -c` — syntax check all modified modules
5. `dev_scripts/install debug && dev_scripts/all` — smoke test sandbox

## What we are NOT doing
- Node spool rewrite (separate effort)
- SyncDictFile → SQLite (node scope)
- Analysis docs / codestyle docs (stay on ai branch)
- CI action version downgrades (regression, skip)
