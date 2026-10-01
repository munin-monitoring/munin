# Mission Log: Test Suite Parallelism + Coverage Path Repair

**Date:** 2026-10-01
**Context:** Follow-up to the FK enforcement log. CI's long pole is the
"Test with coverage" step (`docker-cover`, Devel::Cover over the whole
suite). The mandate: speed up the test suite itself; coverage is a side
effect. Parallelism was the first, naive lever -- this log records what it
actually bought, what it didn't, and the correctness bugs found along the
way.

---

## What We Did

### Part 0: Mission Log Skill Amendment (side quest)

Before the suite work: the mission-log skill itself instructed "Update
README: add a row to the entries table" per log. Amended the skill (in
`~/.agents/skills/mission-log/SKILL.md`) so `mission_log/README.md` stays
generic and long-lasting -- no per-log index. The directory listing (and git
history) is the index; an entries table is churn that conflicts and rots.
Workflow step 4 is now "Do NOT touch the README".

### Part 1: First-Principles Baseline

Everything runs in docker (`localhost/munin-dev`, Debian bookworm, perl
5.36, Devel::Cover 1.38, TAP::Harness v3.44, Module::Build 0.4232, 4 cores
host and container). No `gh` CLI -- analyze from the suite itself.

Serial baseline (`prove --timer -j1 t/*.t`):

```
Files=33, Tests=488, 529 wallclock secs (498 CPU)
```

Per-file costs (wall): spec 103s, graph_static 82.5s, update 44.7s,
graph 42.5s, html_static 37.4s, html 36.6s, limits 36.4s, migrate_rrd
31.4s -- top 8 = 78% of total. The suite is dominated by a handful of
CPU-bound giants (rrdtool/graph/html rendering, SampleDB spec queries).

Module::Build 0.4232 has no `test_jobs` property: `./Build test` is
strictly serial. Parallelism must come from `prove -j` directly.

### Part 2: The Parallel Experiments

| Run | Wall | CPU |
|-----|------|-----|
| -j1 serial | 529s | 498s |
| -j3 | 269s | 669s |
| -j4 | 274s | 654s |

~1.9x, not ~4x. Diagnosis from per-file timings: under -j4 the giants
inflate 1.5-2.5x each other (graph_static 82s -> 145s, html_static 37s ->
95s), total CPU rises ~30% (scheduling/cache overhead + test-internal
forking: node servers, rrdcached, update workers oversubscribe the cores),
and the makespan is set by the last chain, not by average load. -j3 ~= -j4
confirms the suite is past its useful parallelism point: bounded by giant
file cost, not by job slots. `t/munin_master_real_failures.t` (2.1s
serial) ballooned to 82s at -j4 and 12.5s at -j3 -- pure contention
sensitivity, no fixed cost (it is all in-process unit tests).

prove mechanics learned along the way (`prove --help`, `prove -H`):
`--shuffle` (random order), `--state=slow|fast|save|last|failed|hot|adrian`
(persistent duration/failure state in `.prove`), `--rules` (seq/par
patterns), `--timer` (per-file durations in the log), `.proverc`. A
`--state=slow` LPT scheduler was designed (committed state file, or GH
actions cache for CI) and then **dropped by decision**: embrace
`--shuffle`. Rationale: shuffle mixes slow/fast "close enough", is
self-maintaining (no fragile hand-ordered list, no state plumbing), and
double-checks order-independence of tests. The harness log (timer lines +
`Files=` summary) naturally records the order used -- reproduce locally in
docker by passing those files to prove in that order. `ls t/*.t | shuf`:
overkill, prove does it.

### Part 3: Devel::Cover 1.38 -- What Parallel Coverage Actually Costs

Measured factor on a 4-file subset, plain -j4 vs covered -j4:
**40s -> 212s (~5.3x)**, all tests pass under `prove -j4` +
`PERL5OPT=-MDevel::Cover`. So CI's coverage step ~= 5x the suite cost.

First-principles checks against the tool:

- **Per-process DB files:** Devel::Cover writes
  `cover_db/runs/<timestamp>.<pid>` per test process -- parallel collection
  needs no per-.t DB, no locking, no merge choreography. `cover` merges
  runs at report time. The "per .t db" idea was unnecessary.
- **Runtime `-select` does NOT prune collection** in 1.38 (probe: files
  outside the select were still collected). Decorative -- not used.
- **Report-time `-select` does NOT filter** in 1.38 either (identical
  output for matching and non-matching patterns). **`-select_re` (regex)
  does** -- verified: `-select_re "^lib/Munin"` removed the `/usr/bin/prove`
  row; `-select_re "^blib/"` (matches nothing) fell back to showing all.
- Devel::Cover collects branch/condition/statement/subroutine/time; pod
  coverage unavailable (Pod::Coverage not installed).

### Part 4: The Coverage Select Bug (the real find)

The old CI command was `cover -test -select "blib/lib|blib/script"`.
But tests load production code via `use lib qw(lib t/lib)` -- the coverage
db contains `lib/Munin/...` paths, never `blib/lib/...` (verified: collected
db lists `lib/Munin/Master/Limits.pm` etc.; old local HTML artifacts were
named `lib-Munin-*.html`). Therefore:

**CI's coverage upload to Coveralls has been empty all along**, while
paying the full ~5x instrumentation tax. The fix: report-time
`-select_re "^lib/Munin|^script/munin"` (production code as loaded; also
covers `script/munin-*` exec'd by tests; keeps `/usr/bin/prove` out of the
payload). Applied to `docker-cover` (html_basic + summary) and the
workflow's coveralls upload step.

### Part 5: Process Leak in limits.t (found by ps, not by tests)

A ps snapshot mid-run showed `perl t/munin_master_limits.t` with a pile of
zombie `true` children. Investigation:

- `t/lib/SampleDB.pm` gave the test contact `command = /bin/true`.
  `/bin/true` exits without reading stdin -> every notification write hits
  EPIPE -> `Limits.pm` closes the pipe, deletes the cached handle ->
  next notification reforks a new `/bin/true` -> zombie pileup. A pipe
  test double must consume stdin to EOF like a real mailer.
- `lib/Munin/Master/Limits.pm` forked notification commands but
  **discarded `$pid`** -- no `waitpid` anywhere. Every command became a
  zombie until the limits process exited, and **exit status was never
  observed**: a notification command that dies silently was
  indistinguishable from one that delivered. The user's framing: "not
  spinning CPU -- just dirty, and might hide a bug."

Fixes:

- Limits.pm: `%contact_pids` tracks children; `_reap_command()` polls
  `waitpid(WNOHANG)` up to 1s after closing pipes (children see EOF,
  exit, get reaped), WARNs on non-zero exit / signal, WARNs if still
  running after the budget; `exit 127` after a failed exec; broken-pipe
  path reaps too. POSIX `WNOHANG` import.
- SampleDB.pm: `/bin/true` -> `perl -ne1` (consumes stdin, exits 0, no
  output, no shell metacharacters). First attempt used
  `perl -e while(<STDIN>){}` -- exec()'s single-string form saw the `<`
  metachar and fell back to the shell, which parsed `<STDIN>` as a
  redirection from a nonexistent file -> exit 2. The new WARN surfaced it
  immediately ("notification command for testcontact exited with exit
  code 2") -- the visibility fix catching a fixture bug on its first run.

Verification: limits.t passes (43 tests), zero WARN/pipe noise, post-run
zombie count 0 (mid-run 1 = transient reap window, bounded).

### Part 6: Per-.t State Dirs (user's design)

Idea: `/dev/shm/munin-var-lib/$PID/`, mkdir at the start of each `.t`,
auto-cleaned. Implemented `t/lib/TestState.pm`:

```perl
my $dbdir = TestState::state_dir();
# /dev/shm/munin-var-lib/<pid>-XXXXXX/  (File::Temp, CLEANUP => 1)
# falls back to File::Spec->tmpdir when /dev/shm is unavailable
```

PID + random suffix: parallel prove jobs and concurrent local runs cannot
collide; `CLEANUP => 1` removes the tree at process exit **including when
the test dies partway** (the old `CLEANUP => 0` + manual `remove_tree`
pattern leaked on crash). Migrated 18 test files + `t/lib/TestTLS.pm` from
scattered `tempdir("x-$$-XXXXXX", TMPDIR => 1, CLEANUP => 0)` to
`TestState::state_dir()`; killed the hardcoded `/tmp/munin_test` dbdir in
`t/munin_master_update_groups.t`; `t/munin_master_limits_cdef.t` gained
`t/lib` in its `use lib` (it only had `lib`). Spot-checked diffs after the
bulk edits (sed/quantifier gotchas from the FK session still in memory).
`docker-test` shm-size bumped 128m -> 512m (cover 256m -> 1g) since state
now always lives in /dev/shm. `node_test_spool.pl` left on plain tempdir
(docker sets TMPDIR=/dev/shm; noted as follow-up).

### Part 7: Makefile + Workflow

```make
JOBS  ?= $(shell nproc)
TESTS ?= t/*.t
PROVE  = prove --shuffle --timer -j$(JOBS) -Iblib/lib -Iblib/arch
```

- `docker-test` / `docker-test-one` / `docker-show-fail`: `perl Build.PL &&
  ./Build && $(PROVE) ...` (Build test replaced; `./Build` explicit since
  prove needs blib). `docker-show-fail` exit-code bug fixed: the old
  `prove ... | tee log; RC=$?` captured tee's exit (always 0) so the
  failure summary never triggered -- now redirects to a file, cats it,
  then runs show-test-failures on the real status.
- `docker-cover`: `./Build && rm -rf cover_db && PERL5OPT=-MDevel::Cover
  $(PROVE) $(TESTS) && cover -silent -select_re ... -report html_basic
  -outputdir cover_db && cover -silent -select_re ... -summary`.
- Workflow: coveralls upload gets the same `-select_re` filter.
- `MANIFEST.SKIP`: `^out/`, `^\.prove$`. `.gitignore`: `/out/`, `/.prove`.
  (Build.PL had been printing "Added to MANIFEST: out/*.out" during
  configure; SKIP makes that moot.)

### Validation Status (honest)

```
serial baseline ......... ok (33 files, 488 tests, 529s)
-j3 / -j4 baselines .... ok (269s / 274s, all pass)
subset plain -j4 ........ ok (4 files, 40s)
subset covered -j4 ...... ok (4 files, 212s, probe)
limits.t via new
  make docker-test-one .. ok (43 tests, 41s; 0 WARN; 0 zombies)
PENDING: full make docker-test (shuffle -j4, all migrations)
PENDING: docker-cover end-to-end (html_basic + summary + select_re)
PENDING: commits (working tree validated piecemeal, not yet committed)
```

---

## What We Learned

### Technical

1. **Parallel speedup was ~1.9x, not ~4x, and that is structural.**
   makespan = max(total CPU / cores, critical chain) with contention
   inflation; -j3 ~= -j4 proves the suite is bounded by giant-file cost,
   not job slots. Tooling cannot schedule away a 103s file.
2. **CI coverage was uploading EMPTY data while costing ~5x the suite.**
   `-select "blib/lib|blib/script"` vs modules loaded from `lib/` via
   `use lib`. Coverage paths are the paths as LOADED, not as installed.
   Always verify with `cover -summary` after a run.
3. **Devel::Cover 1.38 filter semantics:** report-time `-select` does not
   filter; `-select_re` (regex) does, with a fall-back-to-all quirk when
   nothing matches. Runtime `-select` does not prune collection. Trust
   none of it without a probe.
4. **Devel::Cover parallel safety:** per-process `cover_db/runs/<ts>.<pid>`
   files -- no shared-DB locking problem exists; `prove -j` under
   Devel::Cover just works.
5. **exec() shell fallback:** single-string `exec($cmd)` re-runs through
   the shell when metacharacters are present -- `<STDIN>` became a
   redirection. Fixture commands must be metachar-free unless shell
   semantics are intended.
6. **fork without waitpid = zombie + silent failure channel.** Exit status
   of notification commands was never observable; a broken mailer looked
   like a working one. Reap and report.
7. **Pipe test doubles must consume stdin.** `/bin/true` breaks pipe
   semantics (EPIPE -> refork storm -> zombies). `perl -ne1` reads to EOF,
   exits 0, prints nothing (stdout is closed by Limits.pm for children).
8. **Per-.t state dirs beat TMPDIR-following tempdirs:** PID+random under
   `/dev/shm/munin-var-lib/` = collision-proof, tmpfs-fast, auto-cleaned
   on death. shm budget must follow (512m/1g bumps).
9. **prove scheduling knobs exist** (`--state=slow` LPT, `--rules`,
   `.prove` persistence) but shuffle won on robustness grounds -- see
   decisions.

### Process

1. **Fix correctness before optimizing cost.** The select bug meant the
   most expensive CI step produced nothing; that fix was worth more than
   all the parallelism work combined.
2. **A visibility fix pays for itself immediately** -- the new exit-status
   WARN caught the shell-mangled fixture command on its first run.
3. **ps during a test run found what the test log never showed** --
   zombies and CPU burn are invisible to TAP.
4. **/proc snapshots beat speculation** for "who is burning CPU": two
   snapshots 10s apart with utime deltas settled limits.t (self-CPU, not
   children) in one command.
5. **Embrace-shuffle over state-file scheduling:** marginal makespan gain
   not worth fragile ordering + CI cache plumbing; shuffle also tests
   order-independence. Log the order, reproduce locally.

---

## What We Decided

1. **`prove --shuffle --timer -j$(nproc)`** for all test targets (local
   and CI). No `.prove` state, no committed order list, no CI cache --
   the harness log records the order; reproduce by re-listing files.
2. **Coverage select: `-select_re "^lib/Munin|^script/munin"` at report
   time** (docker-cover summary/html_basic + workflow coveralls upload).
   Old `blib/lib|blib/script` select deleted everywhere.
3. **State dirs: `TestState::state_dir()`** -- per-.t, `/dev/shm` preferred,
   auto-cleaned. No hardcoded `/tmp` paths in tests.
4. **Notification commands are reaped and their exit status is reported**
   (WARN on abnormal exit, 1s WNOHANG budget, warn-and-abandon beyond).
5. **Test pipe doubles consume stdin** (`perl -ne1`), never `/bin/true`.
6. **shm-size: 512m (test) / 1g (cover)** -- state is always in /dev/shm
   now; sizes are estimates until the full run proves them.
7. **Mission log README stays generic** -- skill amended, no index rows.

---

## Rules Added

- **Coverage select matches loaded paths** (`lib/`), not installed ones
  (`blib/`) -- tests `use lib qw(lib t/lib)`. Verify with `cover -summary`.
- **Devel::Cover 1.38: filter with `-select_re` at report time**; `-select`
  and runtime select do not filter/prune. Probe before trusting.
- **fork without waitpid is a bug** -- reap children and surface their exit
  status; a silent child failure is indistinguishable from success.
- **Pipe test doubles must read stdin to EOF**; avoid shell metacharacters
  in exec'd fixture commands (exec falls back to the shell on metachars).
- **Test state: `TestState::state_dir()`**, never `tempdir(CLEANUP => 0)`
  with manual cleanup, never hardcoded `/tmp` paths.
- **Spot-check diffs after bulk test edits** (still true; paid off again
  here with limits_cdef.t's missing t/lib).

---

## What We'd Do Differently

1. **Verify the coverage select before optimizing coverage cost.** We
   measured a 5.3x tax on a step uploading empty data. One
   `cover -summary` after the first covered run would have exposed it.
2. **Fixture review first when chasing test slowness** -- `/bin/true` was
   visible in SampleDB.pm from the start; the zombie ps snapshot just
   confirmed it.
3. **Profile instead of inferring** -- the limits.t self-CPU (38s
   in-process) was chased with Devel::Cover time columns whose units and
   attribution proved inconclusive. NYTProf (needs image support) would
   settle it in one run.
4. **The 1s reap budget is a guess.** Real mailers can take 2-5s (SMTP);
   they would WARN "still running; not reaped" every cycle. Tune against
   real timings or demote to once-per-contact / DEBUG.
5. **shm-size 512m/1g is unvalidated** -- if /dev/shm fills under -j4
   with graph fixtures, failures will look bizarre. Measure actual state
   dir sizes in the full run.

---

## Files Changed

| File | Purpose |
|------|---------|
| `Makefile` | `JOBS`/`TESTS`/`PROVE` vars; docker-test/-one/-show-fail on prove --shuffle -j; docker-cover parallel + fixed select; shm bumps; show-fail exit-code fix |
| `.github/workflows/build-n-test.yml` | coveralls upload gains `-select_re "^lib/Munin|^script/munin"` |
| `lib/Munin/Master/Limits.pm` | `%contact_pids`, `_reap_command()` (WNOHANG poll, exit-status WARNs), exit 127 on failed exec |
| `t/lib/SampleDB.pm` | contact command `/bin/true` -> `perl -ne1` |
| `t/lib/TestState.pm` | NEW: per-.t state dir under `/dev/shm/munin-var-lib/`, auto-cleaned |
| `t/lib/TestTLS.pm` | certs dir via TestState |
| `t/munin_master_{graph,graph_static,html,html_static,graph_html_helpers,handle_request,httpd_graph,lifecycle,limits,limits_cdef,spec,update,update_groups,update_rrdcached,update_rrdcached_integration,update_spoolfetch,configparser}.t`, `t/munin_migrate_rrd.t` | tempdir -> `TestState::state_dir()`; `/tmp/munin_test` removed; limits_cdef gains t/lib |
| `MANIFEST.SKIP` | skip `^out/`, `^\.prove$` |
| `.gitignore` | `/out/`, `/.prove` |
| `~/.agents/skills/mission-log/SKILL.md` | README stays generic; no index rows (outside repo) |
| `mission_log/2026-10-01_test_suite_parallelism.md` | this log |

---

## Test Results

```
serial baseline (prove -j1) ......... ok: 33 files, 488 tests, 529s
parallel -j3 / -j4 .................. ok: 269s / 274s (all pass)
subset plain -j4 .................... ok: 4 files, 40s
subset covered -j4 (probe) .......... ok: 4 files, 212s (~5.3x factor)

# After checkpoint commits + explicit-handle pivot (full_test5):
make docker-test .................... FAIL: httpd_html.t exited 2 (HTML.pm
    opened get_dbh(1) at request start; the test routes path="" -> 301
    redirect, which needs no SQL). Fixed: handle opened per branch.

# After HTML/Limits fixes (full_test6): PASS 33 files, 488 tests, 250s

# After limits restructure (full_test7/8): PASS 33 files, 488 tests,
# 267-281s wall (shuffle variance; CPU-bound giants unchanged)

limits.t solo, post-restructure ..... ok: 43 tests, exit 0
limits.t DBI calls .................. 268,287 -> 204,793 -> 193,732 -> 119,275
limits.t DBI time ................... 30.66s -> 23.58s -> 20.79s -> 13.89s
limits.t DBI connects ............... 754 -> 30
parallel smoke (fork=1, PFM) ........ ok: 300 ds eval across children,
    105 edges, 25 ledger rows, 0 locks, 0 zombies (caught a real bug:
    phase 3 never committed its ledger upserts)
make docker-cover (2-file) .......... exit 0; select_re + html_basic +
    summary all filter to ^lib/Munin|^script/munin; cover_db/coverage.html
    generated (dev image gained libtemplate-perl for Template.pm)
```

### limits.t DBI profile (final)

Top buckets after the restructure (was: ds_attr 61.7k calls/8.3s,
state upsert as two statements, override 21.8k):

```
10,208  service ds listing (phase 2 + phase 3 rebuild)
17,400  state row read (once per ds per pass -- irreducible)
41,419  ds_attr IN-list fetch (was 61,719 single-row; 8.3s -> 1.1s)
 8,787  state upsert (single ON CONFLICT; was INSERT+UPDATE pair)
   748  notification_tracking upsert (ledger; service_id now in key)
```

---

## Commits

All validated; full suite green at every commit boundary via
syntax checks + targeted runs, and the final state twice via full
`make docker-test` (488 tests) + `make docker-cover`.

| Commit | Subject |
|--------|---------|
| 9df6a11b4 | fix: reap notification commands and surface their exit status |
| aabf3487c | test: prescriptive per-.t state dirs via TestState |
| 86e0dfd5d | build: parallel prove-based docker test targets |
| dbf914ed3 | ci: fix empty Coveralls uploads; parallelize docker-cover |
| dabf8859d | refactor: explicit per-phase db handles, no cached connections |
| 906103be7 | refactor(limits): three phases with the state table as transport |

The split (a)-(e) came from CONTINUE.md; hunk-level staging via
`git apply --cached` was needed for Limits.pm (reap hunks vs
handle/perf hunks) and update_groups.t (TestState hunk vs dbh-caller
hunks). Every commit's Limits.pm/Update.pm was syntax-checked in the
container before moving on (bisect safety).

---

## Session Continuation (post-draft)

The draft above was written mid-session. What followed:

### Explicit-handle pivot (proc_dbh removal)

The mid-pivot tree had a process-global cached handle (`proc_dbh`,
invalidated on pid change). Replaced with prescriptive explicit handles:
`get_param`/`get_hosts`/`get_override` die without a `$dbh`; phases
open one, thread it, close it before any fork. `_ro_dbh` (shared reader)
was already gone -- it caused "database is locked" in update_groups.t.

First full run after the pivot failed: **httpd_html.t** exited 2. HTML.pm
opened `get_dbh(1)` at request start, but the test routes `path=""` which
returns a 301 redirect before any SQL. Two fixes: (1) HTML.pm opens the
handle per branch (static branch, main body) -- pure redirects need no
SQL, and every branch `return`s so at most one handle per request; (2)
Limits.pm single-row lookups converted to `selectrow_array` (DBI's own
prepare_cached+execute+fetch+finish) -- the old prepare/fetch pattern
left cursors active and spewed "statement handle still Active" warnings.

### limits restructure (the pivot, completed)

Three phases; the state table is the only channel between them:

1. **Work list** -- per-host services having threshold-ed ds, in memory;
   handle closed before any fork.
2. **Evaluation** -- per-host via Parallel::ForkManager (inline when
   `fork=0`, which tests set); each child opens its own R/W dbh,
   evaluates, writes state, closes. No notification logic in children.
3. **Delivery** -- serial tail in the master; rebuilds messages FROM the
   state table (prev_alarm gives edge detection, eval_value/extinfo are
   the message content), resolves contacts, delivers serialized.

Schema: state gains `prev_alarm`/`eval_value`/`extinfo` (ALTER TABLE
migration for existing DBs, PRAGMA table_info guard on SQLite, IF EXISTS
on Pg). The `notification` table is a send ledger, not config -- renamed
`notification_tracking` (user decision), migrated in place.

### Latent bugs found and fixed along the way

1. **Ledger upsert missing service_id** -- `INSERT INTO notification
   (contact_id, severity, sent_at, num_messages) ON CONFLICT
   (contact_id, service_id)`: service_id not in the INSERT list, so it
   was NULL, NULLs don't collide in the unique index, ON CONFLICT never
   matched, rows grew unbounded and max_messages throttling never
   accumulated. Present since the table was introduced.
2. **Contact id churn** -- `_db_import_config` wiped contact every cycle;
   ledger rows keyed on contact_id reset each run. Now upsert-by-name;
   vanished contacts deleted with their ledger rows (FK, no cascade).
3. **limits_startup dropped** in the SQL rewrite while script/munin-limits
   still called it -- the standalone script died at startup at HEAD.
   Restored (GetOptions + config parse + logger).
4. **Phase 3 never committed** -- caught only by the fork=1 smoke test:
   phase 3 opens its own handle (AutoCommit=0), upserted the ledger, and
   disconnected without commit; the whole delivery rolled back. The old
   code hid this because _process_ds committed per-ds on the same
   handle. Fixed with an explicit commit before disconnect.
5. **Ledger reset semantics** -- old code reset num_messages on pipe-open
   (first service per contact per run), so throttling never accumulated
   for later services. Now: transitions reset the counter (fresh budget
   for a new alarm), repeats of the current state are throttled.

### Coverage path

docker-cover initially failed: `cover -report html_basic` needs
Template.pm, missing from the dev image. User decision: add
`libtemplate-perl` to Dockerfile.dev (CI cache key hashes the file, so
the image rebuilds automatically). Rebuilt, re-ran: exit 0, html_basic +
summary + select_re all filter to `^lib/Munin|^script/munin`.

### Final state

- 6 commits, full suite green (488 tests, 267-281s wall at -j4 shuffle),
  coverage path green end-to-end.
- limits.t DBI calls down 56% from session start (268k -> 119k), DBI time
  down 55% (30.7s -> 13.9s).
- Parallel limits validated (fork=1 smoke: 300 ds across 4 children, no
  lock errors, no zombies).

### What remains (from CONTINUE.md, not started)

1. **Shrink the giants** -- spec/graph_static/html are 78% of serial CPU;
   test-design work, the only remaining big lever.
2. **Reap budget tuning** -- 1s WNOHANG is a guess; real SMTP mailers can
   take 2-5s and would WARN every cycle.
3. **node_test_spool.pl spooldir -> TestState.**
4. **CI coverage budget decision** -- parallel+fixed still ~10-15 min.
5. **Write contention under real fork=1 load** -- deliberately not
   optimized (minimize locked timings later, or advise PostgreSQL).
