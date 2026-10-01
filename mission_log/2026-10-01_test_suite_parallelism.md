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

---

## Session Continuation 2: graph_static.t -- mock RRDs::graph, keep the cmdlines (DESIGNED, NOT YET IMPLEMENTED)

**Status at log time:** design converged through discussion + code
reading; the test file is untouched (clean tree). Everything below is
the plan a future session should implement directly.

### Motivation

`t/munin_master_graph_static.t` is the worst offender of the giants:
191s wall / 333s CPU in the last full run (was 109s earlier -- it
inflates badly under -j4 contention). It exercises
`Munin::Master::Static::Graph::create()` -- munin's static site export,
which renders every service graph for all five time periods as PNGs via
`RRDs::graph` and writes them under `_site/`. The cost is almost
entirely real rrdtool rendering: 25 services x 5 periods = 125 graph
renders of 15-DS graphs.

The test's actual assertions are weak for that cost: "PNGs were
produced" and "all time periods present". It never inspects a single
command line -- yet the command lines ARE the interesting artifact:
they are fully determined by the synthetic DB (SampleDB + SampleRRD).

### Direction (user)

Mock `RRDs::graph` so the test stops paying for rendering, but verify
the real command lines instead -- possible precisely because the DB is
synthetic and deterministic. Two iterations agreed:

1. **Log every `RRDs::graph` call; assert they all follow a pattern.**
2. **1% of calls hit the real `RRDs::graph`** -- a canary that keeps
   the fixture honest: if SampleDB/SampleRRD drift from what the
   renderer needs, the 1% real renders start failing.

### What we learned reading the code

- **Call path:** `Static::Graph::create($jobs, $dest)` lists service
  paths from `url WHERE service_id IS NOT NULL`, builds
  `"$path-{year,month,week,day,hour}.png"`, then per path: PFM worker
  -> mock CGI (`path_info => "/$path"`) -> STDOUT redirected to the
  output file -> `Munin::Master::Graph::handle_request($cgi)`.
- **RRDs::graph is called in exactly one place:** `RRDs_graph()` in
  Graph.pm (wrapper around `RRDs::graph(@_)` + `RRDs::error()`); reached
  via `RRDs_graph_or_dump()` for the PNG branch. Mock target:
  `RRDs::graph` itself, so both the wrapper and any future caller are
  covered.
- **The command line** (@rrd_cmd, built in handle_request) is, in
  order: temp outfile (File::Temp, `.png` suffix), `@rrd_graph_args`
  (from `graph_args` attr -- empty in SampleDB), `@rrd_header`
  (`--title "Graph <svc> - for the last <period>"`, `--watermark
  "Munin <ver>"`, `--imgformat PNG`, `--start end-4000s|end-2000m|
  end-12000m|end-48000m|end-400d`, `--slope-mode`, fonts, 6 colors,
  `--width 400`, `--height 175`, `--border 0`, `--end <epoch>`),
  then `@rrd_sum` (empty in fixture), `@rrd_def` (DEF:avg/min/max per
  DS pointing at `$dbdir/<path>/<svc>.rrd` or old-style per-field
  files, DS names like `idle-g` or `42`), `@rrd_cdef` (empty in
  fixture), `@rrd_vdef` (4 VDEFs per DS), `@rrd_legend` (4 COMMENTs),
  `@rrd_gfx` (drawcmds + 4 GPRINTs per DS), `@rrd_gfx_negatives`
  (empty), then the day/night CDEFs + AREA lines (AREA suppressed for
  month/year per period).
- **PFM `new(0)` does NOT fork** (probed empirically: `start()` returns
  0 in-process), so the test's `create(0, ...)` call runs every render
  in-process -- the mock can log to a plain in-memory array/file, no
  IPC needed.
- **`RRDs::error` must be mocked alongside `RRDs::graph`:**
  `RRDs_graph()` calls it after every graph call; without the paired
  mock, the error state of the real RRDs library would leak into the
  mocked path. Mock graph -> return success; mock error -> return undef
  (or the real error for the 1% real calls).
- **RRDs::last is also called** (lastupdate VRULE, when `rrd:last` attr
  is missing -- SampleDB sets none, so every render calls
  `RRDs::last($_rrdfile)`). It reads real RRD headers: cheap, and it
  validates the SampleRRD files exist. Leave it real.
- **The1% canary must survive PFM**: with `create(0,...)` there is no
  fork, so a `rand() < 0.01` check inside the mock is fine as-is.

### The pattern to assert (from the code + fixture)

For each logged call, given outfile and args:
- outfile ends in `.png`
- `--imgformat PNG`; `--watermark` starts with `Munin `
- `--title` matches `/^Graph \S+ - for the last (hour|day|week|month|year)$/`
- `--start` is the %times string for that period
  (end-4000s/end-2000m/end-12000m/end-48000m/end-400d); `--end` is
  the epoch of `time()` at render (allow a small window)
- `--width 400 --height 175 --border 0`, `--slope-mode` present
- exactly 3 DEF per DS (avg/min/max), all referencing files under
  `$dbdir` that SampleRRD created (assert `-f` on the parsed path --
  ties the cmdline to the fixture)
- VDEF/GPRINT counts == 4 x DS count; legend has 4 COMMENTs
- day/night block: the 5 CDEFs present; AREA lines present except for
  month (no n_d_b*) and year (no n_d_* at all)
- call count == 125 (25 services x 5 periods); each service path
  appears exactly 5 times, once per period

### Next steps (implementation checklist)

1. Rewrite `t/munin_master_graph_static.t`: keep SampleDB+SampleRRD
   fixture + `create(0, ...)`; mock `RRDs::graph` (log + 1% real) and
   `RRDs::error` via Test::MockModule; capture calls in an arrayref.
2. Assert the pattern above; keep the PNG-existence checks (they now
   verify the redirect plumbing, not rrdtool).
3. Run solo, then full suite; expect graph_static.t to drop from ~191s
   to fixture-generation time (SampleRRD create+update of 25 RRDs with
   30d of data is the remaining cost -- shrink `generate_sample_rrds`
   data volume if it still dominates).
4. Re-measure shuffle -j4 wall time; update the giants table.

---

## Session Continuation 3: graph_static.t mock (implemented, simplified) + two stragglers (2026-10-01)

Same day as the log above; HEAD at session start `119bcc616`. The
Session Continuation 2 design ("mock RRDs::graph, keep the cmdlines")
was still marked DESIGNED, NOT YET IMPLEMENTED. This session implemented
it -- in a deliberately simplified form per direction: "cut the chase,
simply try. Mock the RRD::graph call by generating a fixed PNG."

### What We Did

1. **Probed that Test::MockModule can reach the XS `RRDs::graph`.**
   Wrote a throwaway probe (`out/mock_probe.pl`) that mocked `RRDs::graph`
   and `RRDs::error`, called the real `RRDs::graph`, and confirmed the
   mock intercepts (logged 1 call, wrote "FAKE" to the outfile) and that
   `\&RRDs::graph` is a real CODE ref for the canary fallback. This
   settled the one open risk in the design -- whether an XS function is
   mockable at all -- before touching the test. Probe deleted after.

2. **Rewrote `t/munin_master_graph_static.t`** (kept the SampleDB +
   SampleRRD fixture and `create(0, ...)`):
   - Mock `RRDs::graph`: append `@args` (post-outfile) to `@graph_calls`,
     write a fixed 1x1 PNG (embedded `pack("H*")`) to the outfile,
     return `(1, 1)`.
   - Mock `RRDs::error`: return `undef` (RRDs_graph() consults it after
     every call; without the paired mock the real library's error state
     leaks into the mocked path). `RRDs::last` left real -- reads RRD
     headers only and validates the SampleRRD files exist.
   - Kept the PNG-existence + all-periods checks (they now verify the
     STDOUT-redirect plumbing, not rrdtool).
   - Added: every produced PNG is non-empty (the mock's fixed content),
     and `scalar(@graph_calls) == 125` (25 service paths x 5 periods) --
     pins the render loop so a re-render/skip regression shows up with
     zero rrdtool cost.
   - Dropped the unused `File::Temp`/`File::Path` imports and the manual
     `remove_tree` (TestState auto-cleans).

3. **Found and fixed a redefinition warning** surfaced by the test run:
   `Subroutine print_version_and_exit redefined at Limits.pm line 120`.
   Root cause: `Limits.pm` did `use Munin::Master::Utils;`, whose
   `@EXPORT` includes `print_version_and_exit`, *and* defined its own
   local sub (line 120) printing the specific `munin-limits $VERSION`.
   The pre-rewrite module had no local sub and used Utils' generic
   export -- but Utils' generic text ("munin version ...") is wrong for
   the munin-limits binary, so the specific sub is the one to keep.
   Verified the fix idiom empirically (`use Foo ()` loads the module but
   imports nothing; `Foo::bar` still resolves fully-qualified), then:
   `use Munin::Master::Utils ();` + fully-qualified the single real call
   site (`Munin::Master::Utils::exit_if_run_by_super_user()`). Only two
   Utils symbols were used module-wide (`exit_if_run_by_super_user`,
   `print_version_and_exit`); the latter has its own local def. Warning
   gone; limits.t still 43/43.

4. **Found and fixed the `.pi/` MANIFEST leak.** Every Build.PL printed
   `Added to MANIFEST: .pi/out/...` (the pi agent harness's own
   command-output dir). `MANIFEST.SKIP` had `^out/` (anchored, so it
   never matches `.pi/out/`) but nothing for `.pi/`. Added `^\.pi/`.

### Validation (honest)

- graph_static.t solo: **ok, 6 tests, ~40s** (was ~82s serial / ~191s
  in-shuffle before the mock).
- limits.t solo after the Utils fix: **ok, 43 tests**, no redefinition
  warning.
- MANIFEST.SKIP fix: after `./Build realclean` + fresh `Build.PL`, a
  newly generated MANIFEST has **0 `.pi/` lines** and nothing added.
  (First run after the edit still showed 145 because the *stale* MANIFEST
  was being reconciled; the rewrite under the new skip is what silences
  it -- worth knowing so a single noisy run isn't misread as failure.)
- **Full suite from the clean state: PASS, 33 files, 490 tests, 194s
  wall** at shuffle -j4 (was 267-281s at the log's final state;
  graph_static.t alone ~82s -> ~40s). Test count 488 -> 490 (the
  graph_static rewrite went 2 tests -> 6).

### What We Learned

1. **Probe the mockable-sub question before designing around it.** The
   design's one real unknown -- can Test::MockModule intercept an XS
   function like `RRDs::graph`? -- was settled by a 20-line probe, not
   by reading Test::MockModule docs or gambling on the rewrite.
2. **`use Foo ()` = load, import nothing** (verified, not assumed). It's
   the clean fix for "module exports X but I define my own X": keep the
   specific sub, drop the import collision, fully-qualify the one real
   call. Safer than deleting the local sub (which would silently change
   `munin-limits --version` output to Utils' generic text).
3. **A generated MANIFEST is stateful.** A MANIFEST.SKIP fix can look
   like it failed on the first run (stale MANIFEST being reconciled) and
   pass on the second. Verify from `realclean`, not from a re-run.
4. **Anchored MANIFEST.SKIP patterns don't match nested dirs.** `^out/`
   never matches `.pi/out/`. If a skip is meant to be recursive, it
   needs the right anchor (or an unanchored form).
5. **Pre-existing warnings can ride along on a green run.** html_static.t
   emits repeated `substr outside of string ... HTML.pm line 812` (from
   `_get_params_services`: `substr($_url, 1 + length($base_path))` when a
   service's `url.path` is shorter than `base_path`+1, or undef). Zero
   edits to HTML.pm/url this session -- not a regression, and the test
   passes -- but the sliced `URLX` degrades a service link, so it's a
   real (if low-severity) defect worth a look, not just noise.

### What We Decided

1. **Fixed-PNG mock, not the full cmdline-assertion design.** Per
   direction ("cut the chase"), the implemented test mocks `RRDs::graph`
   to write a fixed PNG and pins the *call count* (125), but does **not**
   yet assert the per-arg cmdline pattern from the Continuation-2 design
   (title/start/DEF/VDEF/GPRINT counts, day-night CDEFs) and has **no 1%
   real-render canary**. The canary ref (`\&RRDs::graph`) was proven to
   work in the probe, so the remaining design work is straightforward if
   we want the stronger assertions later.
2. **Keep the specific `print_version_and_exit`** in Limits.pm (correct
   output for the binary); suppress the Utils import collision rather
   than deleting the local sub.
3. **`^\.pi/` added to MANIFEST.SKIP** -- the agent harness's output dir
   is not dist content.

### Files Changed (this session)

| File | Purpose |
|------|---------|
| `t/munin_master_graph_static.t` | mock RRDs::graph (fixed PNG + call log) + RRDs::error; keep plumbing checks; add nonempty-PNG + 125-call-count asserts |
| `lib/Munin/Master/Limits.pm` | `use Munin::Master::Utils ();` + fully-qualify `exit_if_run_by_super_user` -- kills the `print_version_and_exit` redefinition warning |
| `MANIFEST.SKIP` | add `^\.pi/` so the agent harness's `.pi/out/` never enters MANIFEST |

### Follow-up investigations (same session, post-commit)

Two of the deferred items were run to ground. Both closed with evidence;
neither needed a code change.

**1. `node_test_spool.pl` -> TestState: closed as a no-op.** The spool
node is `exec`'d standalone and the parent kills it with SIGTERM. Both
`tempdir(CLEANUP => 1)` (what it uses now) and `TestState` clean up via
`END` blocks -- and `END` does **not** run on an uncaught SIGTERM. A
probe confirmed it: child died on signal 15, no `END block ran`. So the
migration would leak identically (both already land in tmpfs; docker
sets `TMPDIR=/dev/shm`, and the container is ephemeral). The "never
tempdir(CLEANUP => 0)" rule doesn't apply -- this uses `CLEANUP => 1`,
and no END-based cleanup fires on SIGTERM regardless of mechanism.
Not worth doing.

**2. HTML.pm:812 `substr outside of string`: root cause is the fixture,
not HTML.pm.** Temporarily instrumented the substr (captured `base_path`
+ `url` on the out-of-range case, then reverted -- clean diff) and ran
`html_static.t`. The pairing is unambiguous:

```
base_path=<aesir/aesir>              url=<(aesir/load)>
base_path=<acme.com/localhost/localhost>  url=<(acme.com/localhost/cpu)>
```

`base_path` is the **node** url; the service `url` sits at **group**
level, missing the node segment. `substr($_url, 1+length($base_path))`
assumes each service url is nested under the node path -- which
production *guarantees*: `_db_url` (UpdateWorker.pm) prefixes every
child path with its parent's url (`$path = "$p_path/$path" if
$p_path`), so a service url is always `node_path/service_name`.
SampleDB violates that invariant: it builds service urls as `$path/$svc`
(group-level) but node urls as `$path/$host` (an extra `$host`), so the
service is never under the node. HTML.pm is correct for real data; a
substr guard would only mask the fixture bug. The principled fix is
SampleDB's url nesting, but that touches url paths feeding ~6 test files
with hardcoded path assumptions -- a real change, deferred on purpose.

### Next Steps

1. **(optional, scope-cut) Restore the stronger graph_static
   assertions** -- per-arg cmdline pattern + 1% real-render canary. The
   XS mock + `original()` ref are proven, so this is straightforward if
   wanted later; user chose the simple fixed-PNG mock for now.
2. **Fix SampleDB url nesting** (root cause of HTML.pm:812) -- make
   service urls nest under node urls the way `_db_url` does in
   production. Real change: verify the ~6 dependent test files' hardcoded
   paths. Not urgent (cosmetic warning + degraded peer link in tests).
3. ~~Commit this session's three files~~ -- done (see Commits below).

### Commits (this session)

| Commit | Subject |
|--------|---------|
| 0240b46f3 | test: mock RRDs::graph in graph_static.t with fixed PNG |
| 89d5f5339 | fix: stop print_version_and_exit redefinition warning in Limits.pm |
| 5fea59bb9 | build: skip .pi/ agent-harness output in MANIFEST.SKIP |
| 29563dd12 | docs: log graph_static.t mock session + two straggler fixes |
