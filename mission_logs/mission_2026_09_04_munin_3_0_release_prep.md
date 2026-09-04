---
name: munin-3.0-release-prep
description: Finalize inflight items and release Munin 3.0
type: mission
date: 2026-09-04
---

# Mission Log: Munin 3.0 Release Prep — 2026-09-04

## Objective

Finalize all inflight work and release Munin 3.0 with bug fixes,
master-side SQL-first persistence, enhanced tests, and improved dev
environment.

## The Crash

Integration tests failed with "Socket read failed" in Docker:

```
[FATAL] Socket read from aegir.alfheim.aesir failed. Terminating process.
Failed to connect to node testing.acme.com:24950/tcp : Invalid argument
Failed to connect to node localhost:24949/tcp : Connection refused
```

Also, limits module crashed on startup:

```
Undefined subroutine &Munin::Master::Utils::munin_get called at
/app/blib/lib/Munin/Master/Limits.pm line 193.
```

## Root Cause Chain

1. `munin_get` and related functions were deleted from Utils.pm in
   commit 75a82257 (2018) but Limits.pm still called them
2. Limits.pm was the last holdout using the old config-tree-walking API
3. The proper fix was SQL-first: all data from DB, no Perl struct walking
4. Integration tests failed because IO::Socket::IP with LocalAddr '::'
   (IPv6) hangs when connecting to IPv4 127.0.0.1
5. Docker regenerates /etc/hosts at runtime, overwriting Dockerfile
   entries for testing.acme.com

## Dead Ends Explored

### Attempt 1: Restore munin_get from git history

Tried restoring the deleted functions from before commit 75a82257.
Failed because the functions were intentionally removed as part of the
SQL-first migration. Restoring them would revert the architecture.

### Attempt 2: Cherry-pick ai branch limits changes

The ai branch had SQL-first limits work, but it depended on other ai
commits. Cherry-picking created a broken dependency chain.

### Attempt 3: Use munin-node-debug for integration tests

The existing munin-node-debug stress test tool was used in the original
tests. It failed in Docker because it binds to localhost (IPv6 ::1)
while workers connect to 127.0.0.1 (IPv4). Also, its fork-per-
connection model caused race conditions with the test's own forking.

### Attempt 4: Port-polling for node readiness

Replaced sleep(5) with IO::Socket port polling. The node started and
ports were open, but connections still failed at the protocol level.
The issue was IPv4/IPv6 mismatch, not timing.

## Resolution

### SQL-First Limits Rewrite (23 commits on top of origin/master)

1. Cherry-picked 3 bug fixes from ai branch:
   - Centralize get_param() into Update.pm
   - Hardens limits/update state handling
   - Fix first-sample preservation and custom RRA

2. Rewrote Limits.pm from scratch:
   - Zero Perl struct walking, everything from SQL
   - New tables: contact, contact_attr, override, notification
   - Config imported once at startup via _db_contacts_update
   - Override table for config file values (two-step query)

3. Fixed integration tests:
   - Set local_address 0.0.0.0 in test config
   - Replaced munin-node-debug with minimal test nodes
   - Added --add-host testing.acme.com:127.0.0.1 to CI

### Integration Test Fix

Root cause: IO::Socket::IP->new(LocalAddr => '::') hangs on IPv4.
Fix: local_address 0.0.0.0 in t/config/munin.conf.

Root cause: /etc/hosts overwritten by Docker at runtime.
Fix: --add-host testing.acme.com:127.0.0.1 in docker run.

Root cause: munin-node-debug fork model incompatible with test.
Fix: Single-process test node with IO::Select.

## Key Insight

The entire Munin architecture was designed around config-tree walking.
The SQL-first approach requires that ALL components read from DB after
startup. The config tree is a one-time import — never queried again.
This eliminates hidden Perl state and makes everything inspectable
via sqlite3.

## Remaining Work

- [ ] Generate RRD files at test time instead of committing binaries
- [ ] Rewrite Config.pm + Defaults.pm for runtime configuration
- [ ] Node rewrite (separate effort)
- [ ] Tag and build tarball (needs build deps)

## Bugs Found and Fixed

### Bug 1: munin_get undefined

**Symptom:**
```
Undefined subroutine &Munin::Master::Utils::munin_get called at
lib/Munin/Master/Limits.pm line 193.
```

**Root cause:** Functions deleted from Utils.pm in 2018 but Limits.pm
still called them.

**Fix:** Complete rewrite of Limits.pm to use SQL queries only. No
more munin_get calls.

### Bug 2: Alarm never updated

**Symptom:** State alarm was always the old value, never the new one.

**Root cause:** Line 554 had `my $new_state = $old_state` — the
computed state was thrown away.

**Fix:** Track $new_state through all branches, write to SQL at end.

### Bug 3: First sample lost

**Symptom:** First data sample after INSERT was never written.

**Root cause:** INSERT without subsequent UPDATE in _db_state_update.

**Fix:** Re-execute UPDATE after INSERT.

### Bug 4: Custom RRA broken

**Symptom:** Custom resolution RRAs used un-enlarged values.

**Root cause:** Iterated @resolutions_computer instead of
@enlarged_resolutions.

**Fix:** Use @enlarged_resolutions in the RRA creation loop.

### Bug 5: to_sec() case sensitive

**Symptom:** "S" vs "s" mismatch in time unit parsing.

**Root cause:** Regex matched case-insensitively but hash lookup was
case-sensitive.

**Fix:** lc($2) before hash lookup.

### Bug 6: Integration tests fail in Docker

**Symptom:**
```
[FATAL] Socket read from aegir.alfheim.aesir failed.
```

**Root cause:** IO::Socket::IP with LocalAddr '::' hangs on IPv4.
Also, testing.acme.com not in /etc/hosts (Docker overwrites it).

**Fix:** Set local_address 0.0.0.0 in test config. Use --add-host
for DNS. Replace munin-node-debug with minimal test nodes.

### Bug 7: SQL quoting error

**Symptom:**
```
Bad name after ds' at lib/Munin/Master/Limits.pm line 304.
```

**Root cause:** Single quotes inside single-quoted string.

**Fix:** Use q{} quoting for SQL with embedded quotes.

## Lessons

- SQL-first means zero Perl struct walking after startup. If you see
  munin_get/munin_set_var_loc, it's the old way.
- The override table pattern (ds_attr + override, two-step query)
  preserves provenance while allowing config file overrides.
- IO::Socket::IP with LocalAddr '::' does not fall back to IPv4.
  Always set local_address explicitly in test configs.
- Docker regenerates /etc/hosts at runtime. Use --add-host instead
  of Dockerfile entries for hostname aliases.
- Single-process test servers (IO::Select) are more reliable than
  fork-per-connection models in containerized environments.
- Commit semantically after each interaction for git bisect.
