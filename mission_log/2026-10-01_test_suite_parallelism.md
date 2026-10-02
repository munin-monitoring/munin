# Mission Log: Test Suite Parallelism + Coverage Path Repair

**Date:** 2026-10-01
**Context:** Follow-up to the FK enforcement log. CI's long pole is the
"Test with coverage" step (`docker-cover`, Devel::Cover over the whole
suite). The mandate: speed up the test suite itself; coverage is a side
effect. Parallelism was the first, naive lever -- this log records what it
actually bought, what it didn't, and the correctness bugs found along the
way.

---

## Working Directives (from the user, 2026-10-01/02)

Recorded here because a new session reads AGENTS.md and this log, not the
conversation history. Several of these override or clarify standing
instructions -- applying AGENTS.md verbatim would trip over them.

1. **(REVOKED 2026-10-02) ~~The bash output plugin allows unlimited
   output -- do not redirect or pipe.~~** The user crafted a bash output
   plugin; the standing AGENTS.md advice ("debug: files not pipes ->
   run `cmd > out/cmd.out 2> out/cmd.err`, then read/grep those files")
   was superseded. **The plugin has since been removed**, so the
   AGENTS.md advice is back in force: for debug output, redirect to
   files (`> out/cmd.out 2> out/cmd.err`) and read/grep the files.
   Directives 2-6 below remain correct.

2. **Use the `read` tool for file contents, not bash.** No `sed -n`,
   `cat`, `head`, `tail`, or bash `grep` to inspect a file. Corrected
   twice early ("use read for it"; "avoid using bash for reading files,
   grepping and using head/tail"). Bash is for *running* things --
   tests, git, perl one-liners -- not for reading files.

3. **Use `edit` for changes, not full-file rewrites.** "use edit not
   rewrite which is more error prone." Surgical `edit` calls with exact
   `oldText` are preferred; whole-file `write` is the error-prone path.
   One accepted exception this session: byte-identical multi-site
   substitutions (8+ identical call sites) went through a scoped
   `perl -pi` after grep-confirmed identity -- still not a rewrite, and
   still diff-reviewed afterward.

4. **Explain every deviation from the common method in a comment.**
   "if not using the common method, always explain why in a comment."
   This became a project rule (Continuation 6) and was applied
   retroactively across the suite -- 13 justifications in 12 files.

5. **Prefer the simple working solution over the elaborate design.**
   On the graph_static mock: "let's just cut the chase and simply try.
   Mock the RRD::graph call by generating a fixed PNG." The fixed-PNG
   mock shipped; the stronger per-arg cmdline-assertion design stayed
   optional and unimplemented.

6. **Append to the mission log at the end of each session.** "and of
   course, do append to the mission log at the end." Work is committed
   first, then documented -- and "update mission log.
   comprehensively" means the full treatment, not a stub.

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
| d667ff189 | docs: record two follow-up investigations (TestState no-op, HTML.pm root cause) |

---

## Session Continuation 4: SampleDB url nesting -- the HTML.pm:812 fix (2026-10-02)

Continuation 3 root-caused the `substr outside of string` warning to the
SampleDB fixture (service urls not nested under node urls) and deferred
the fix as "a real change." User chose to do it. This session implements
it, and the work turns up a second latent bug that had been hiding
behind the first.

### What We Did

1. **Confirmed the production invariant before touching anything.**
   `_db_url` (UpdateWorker.pm:246) prefixes every child path with its
   parent's url: `_db_url("service", $service_id, $plugin, "node",
   $node_id)` (line 472) makes `service.url.path = node.url.path + "/" +
   plugin`. SampleDB built service paths from the group-level `$path`
   (`"$path/$svc"`), so the service was never under its node -- the
   `substr($_url, 1+length($base_path))` in `_get_params_services`
   overran and returned undef.

2. **Found that production never populates `service.path`.**
   UpdateWorker.pm:376 does `INSERT INTO service (node_id, name)` -- no
   path column. So SampleDB writing a path into `service.path` is itself
   non-production behavior. Checked the only two readers: HTML.pm:702's
   `s.path` is a **derived-table alias** (`LEFT JOIN (SELECT ... u_s.path
   AS path ...) AS s`) so it resolves to the *url* path, not the column;
   Graph.pm:982's `s.path` IS the real column but only as an optional
   alias-match fallback (`s.name = ? OR s.path = ?`) that is dead in
   production (column always NULL). And lifecycle.t:269 queries
   `service WHERE path = 'svartalfar/load'` -- a direct read of the
   column that constrains the fix.

3. **Split the two concerns** rather than nesting both. Kept `$svc_path`
   (group-level) in the `service.path` column for lifecycle.t; wrote the
   new node-nested `$svc_url_path = "$node_url_path/$svc"` into the `url`
   table where HTML.pm reads it. `rrd:file` left untouched, so RRD
   resolution (`File::Spec->catfile($dbdir, rrd_file)`) still matches
   where SampleRRD wrote the files.

4. **The fix exposed a second latent bug.** First run: graph_static.t and
   html_static.t each failed 2 tests. Probe (mkdir two-level tree, run
   `glob("**/*.png")`): **core Perl glob does NOT recurse -- `**`
   degenerates to `*`** (matched `a/f1.png`, not `a/b/f2.png`). The globs
   had passed *by accident* on the old flat layout (aesir-family service
   pages sat at exactly one directory level). Nesting deepened the `_site`
   output by one level, so the non-recursive globs matched nothing.

5. **Fixed the globs to match their intent** -- replaced `glob("**/*.x")`
   with an `rglob()` File::Find helper in three tests: graph_static.t,
   html_static.t, and spec.t (spec.t also had the latent `**/*.rrd` and
   `**/*.png` bugs). html_static.t was a near-full rewrite (several
   `**/*.html` sites were byte-identical, so targeted edits could not
   address them uniquely).

6. **spec.t:17 was caught ONLY by the full suite.** My targeted 4-test
   run (lifecycle, html_static, graph_static, html) passed; the
   CI-equivalent `make docker-test` caught `Graph: static generation`
   failing on the same non-recursive glob. This is the project rule
   "local pass != CI pass" earning its keep -- spec.t was not in my
   subset.

7. **Proved warning provenance by stash-compare.** The full-suite output
   carried `Limits.pm:549`, `HTML.pm:812`, `Graph.pm:765` (`$tpng`), and
   `Graph.pm:869` (`$legend`) warnings. Rather than assume, stashed the
   changes and re-ran the 4 warning-emitting tests at the last commit:
   **all four fire in the baseline too** -- none introduced here. And
   HTML.pm:812 fires heavily in the baseline but is *gone* with the fix,
   confirming the fix does what it claims. (The baseline graph.t also
   prints `valid_path: acme.com/localhost/cpu`; with the fix it is
   `acme.com/localhost/localhost/cpu` -- direct evidence of the nesting.)

### What We Learned

1. **Core Perl `glob('**/*.x')` does not recurse.** `**` silently
   degenerates to `*`. Verified by probe, not docs. For "any depth" use
   `File::Find` (or `bsd_glob` with the right flags). This bug was latent
   in three tests and only surfaced when the fixture got *more correct*.
2. **A correct fixture fix can expose latent test bugs that passed by
   accident.** The globs were always wrong; the flat url layout was
   masking them. Making the data match production pulled the rug out.
3. **Targeted test runs miss regressions.** spec.t:17 failed only in the
   full suite -- it wasn't in the 4-test subset. The CI-equivalent full
   run before commit is non-negotiable (project rule, and it caught a
   real failure here).
4. **Stash-compare is the definitive way to prove warning provenance.**
   "I didn't touch that file" is a hypothesis; re-running the same tests
   at the parent commit with the changes stashed is proof. It also
   doubled as positive confirmation of the fix (812 gone with, present
   without).
5. **`service.path` is legacy; `url.path` is the real consumer.**
   Production never writes `service.path`; every HTML/Graph/Static query
   joins `u.path`. When a fixture writes both from one variable, the
   invariant that matters is the url one -- but a test reading the
   legacy column (lifecycle.t) forces you to keep both, not collapse
   them.

### What We Decided

1. **Nest the service `url.path` under the node; leave `service.path`
   group-level.** Production-faithful where it matters (the url table),
   and lifecycle.t:269 keeps working untouched. Nesting both would have
   broken that test for no benefit -- the column is dead in production.
2. **Fix the test globs, not the fixture depth.** The globs' *intent* was
   "any depth"; they were buggy. Reverting the nesting to satisfy a
   non-recursive glob would enshrine the bug.
3. **rglob() as a local helper per test file** (not a shared t/lib
   module) -- three small self-contained copies, consistent with the
   tests' existing style.

### Files Changed

| File | Purpose |
|------|---------|
| `t/lib/SampleDB.pm` | split `$svc_path` (service.path column, group-level) from `$svc_url_path` (url table, node-nested); rrd:file untouched |
| `t/munin_master_graph_static.t` | rglob() replaces non-recursive `**/*.png` globs |
| `t/munin_master_html_static.t` | rglob() replaces `**/*.html` / `**/*cpu*.html` / `**/localhost/*.html`; near-full rewrite (identical lines) |
| `t/munin_master_spec.t` | rglob() replaces `**/*.rrd` and `**/*.png` globs (Part 2 + Part 17) |

### Test Results

```
targeted 4-test run (post-fix) ....... ok 80 tests, 121s
    (lifecycle, html_static, graph_static, html)

full make docker-test ............... FAIL: spec.t:17 (Graph: static
    generation) -- non-recursive glob; NOT in the 4-test subset.
    Also surfaced pre-existing Limits.pm:549 / Graph.pm:765+869 warnings.

full make docker-test (post-rglob) ... PASS 33 files, 490 tests, 201s
    wall at shuffle -j4.

stash-compare at last commit ......... all four warnings (Limits:549,
    HTML:812, Graph:765, Graph:869) present in baseline -> pre-existing,
    none introduced here. HTML:812 fires in baseline, gone with fix.
    valid_path: acme.com/localhost/cpu (baseline) ->
    acme.com/localhost/localhost/cpu (fixed) = nesting evidence.
```

### Commits

| Commit | Subject |
|--------|---------|
| 5b1446128 | test: nest SampleDB service urls under nodes; fix non-recursive globs |

### Next Steps

1. ~~Fix SampleDB url nesting~~ -- **done** (this session).
2. **(optional, scope-cut) Restore the stronger graph_static
   assertions** -- per-arg cmdline pattern + 1% real-render canary. XS
   mock + `original()` proven; straightforward if wanted later.
3. **Reap budget tuning** -- 1s WNOHANG is a guess; real SMTP mailers
   take 2-5s and would WARN every cycle.
4. **CI coverage budget decision** -- parallel+fixed select still ~10-15
   min.
5. **Write contention under real fork=1 load** -- deliberately not
   optimized; minimize locked timings later, or advise PostgreSQL.
6. **Pre-existing warnings** (out of scope here, proven not to be
   regressions): Limits.pm:549 `$dbdir` undef in `_compute_cdef_value`,
   Graph.pm:765 `$tpng` / 869 `$legend` uninitialized in the DEBUG
   timing/legend paths.

---

## Session Continuation 5: factoring shared test setup into TestUtils (2026-10-02)

Session 4 left three byte-identical `rglob` subs in the test suite (one
per file that needed them). User asked to factor that into a test utils
module and survey what else could be factored. The survey found
considerably more duplication than just rglob, and the cleanup surfaced
a pile of dead imports left behind by earlier sessions.

### What We Did

1. **Surveyed for duplication by repeated body, not by name.** Grepped
   for the candidates that had accumulated across the SampleDB/TestState
   work:
   - `rglob` sub: 3 byte-identical copies (graph_static.t,
     html_static.t, spec.t).
   - `get_param` mock closure: 5 byte-identical copies (graph.t, html.t,
     graph_static.t, html_static.t, spec.t).
   - config-setup block (`Config->instance` + `parse_config_from_file` +
     `TestState::state_dir` + dbdir/tmpldir): 4 identical (graph.t,
     html.t, graph_static.t, html_static.t).
   - SampleDB+SampleRRD generation: 9 files; a further 4 use
     SampleDB-only (no RRDs).
   - `Logger::configure`: 14 sites; `parse_config_from_file`: 8 sites --
     surveyed, deliberately not factored (see Decisions).

2. **Created `t/lib/TestUtils.pm`** with four helpers, each documented
   with its call-site example:
   - `rglob($dir, $re)` -- recursive glob via File::Find (core
     `glob('**/*.x')` does not recurse).
   - `setup_test_config()` -- parse t/config/munin.conf, allocate a
     TestState dbdir, set tmpldir; returns `($config, $dbdir)` so
     callers add extra keys (staticdir, fork) on top.
   - `generate_sample_data($dir, $with_rrds)` -- SampleDB (+ SampleRRD
     unless `$with_rrds` is 0); returns the db path.
   - `mock_update_get_param($config)` -- installs the get_param mock,
     returns the Test::MockModule so the caller holds it in scope.

3. **Converted 9 test files** to the helpers. Net **-122 lines** across
   those files (40 insertions, 162 deletions).

4. **Cleaned up dead imports** the factoring exposed (straggler
   discipline: grep for what became unused after removing code):
   - `use File::Temp qw(tempdir);` in **8 files** -- `tempdir()` was
     never called in any of them; the tests had migrated to
     `TestState::state_dir()` in an earlier session but the import was
     left behind. Proven dead: no `tempdir(` call and no `File::Temp->`
     usage anywhere (the only `->new(` hits were CGI and
     Test::MockModule).
   - `use Test::MockModule;` in html_static.t -- its only use (the
     get_param mock) moved to TestUtils.
   - `require SampleDB;` in spec.t -- its only call moved to
     `generate_sample_data`.

5. **Verification:** `perl -c` on all 10 touched files (all OK), then
   the full CI-equivalent `make docker-test`.

### What We Learned

#### Technical

1. **Factor by repeated body, not by name.** The strongest duplication
   signal was byte-identical sub/closure bodies (rglob x3, get_param
   mock x5). A one-line repeated call (`Logger::configure`) is not worth
   a helper; a 6-line identical sub is.
2. **Dead imports accumulate across sessions.** The 8 dead
   `File::Temp qw(tempdir)` imports were residue of the earlier
   TestState migration: the code that used `tempdir()` was replaced,
   but the import was never removed. Every refactor that replaces a
   module's calls should grep for that module's now-unused imports.
3. **A helper that returns the mock keeps ownership explicit.**
   `mock_update_get_param` returns the Test::MockModule because the mock
   dies with the object -- if the helper created and discarded it, the
   mock would vanish before the test ran. Documenting that in the pod
   prevents a future "simplify" that breaks it.
4. **Positional boolean args are opaque at call sites.**
   `generate_sample_data($tmpdir, 0)` -- the `0` means "no RRDs" but
   reads as a mystery. Noted as a design smell; a named param or split
   functions would read better. Left as-is this session (mechanical
   change, not worth the churn), flagged for later.
5. **What *not* to factor matters as much as what to.**
   `Logger::configure` (args vary: info vs error, and some tests depend
   on the level), `parse_config_from_file` (4 standard-conf sites
   factor; the other 4 parse a *generated* `$conf_file` with different
   keys -- forcing them into one helper needs an option bag that
   obscures more than it dedups), DBI connect boilerplate (3-way
   variance: dbname DSN vs dburl vs `$ENV{MUNIN_DBURL}`, rw vs ro).
   Unifying these would trade visible variance for hidden parameters.

#### Process

1. **The straggler rule paid off immediately.** AGENTS.md's "grep for
   stragglers after removing code, functions, or exports" found three
   dead imports in the very files just edited. Without it they'd have
   shipped.
2. **One multi-part edit misfired; reading the result caught it.** The
   html_static.t import-block edit dropped `use File::Path
   qw(remove_tree);` (still needed -- the test calls
   `remove_tree($dbdir)`) and left a duplicate `use TestUtils;` because
   TestUtils had been added earlier in the same file. Reading the file
   back after the edit surfaced both; a follow-up edit fixed it. Rule:
   after an edit that touches adjacent import lines, read the block back
   before moving on.
3. **Mechanical multi-site replacement belongs in `perl -pi`, not the
   edit tool.** Eight byte-identical `= rglob(` call sites and eight
   identical `use File::Temp` lines: the edit tool requires unique
   matches, so a scoped `perl -pi -e` substitution was the right tool --
   but only after confirming the pattern was truly identical everywhere
   (grep first).
4. **Full suite even for mechanical refactors.** The change touched 10
   files of test infrastructure; the suite is the only thing that proves
   the helpers behave identically to the code they replaced. 184s is
   cheap insurance.

### What We Decided

1. **TestUtils.pm holds exactly four helpers** (rglob,
   setup_test_config, generate_sample_data, mock_update_get_param). One
   module for shared test plumbing, alongside the existing
   TestState/TestTLS/SampleDB/SampleRRD -- not folded into TestState,
   whose charter is state directories.
2. **setup_test_config returns `($config, $dbdir)`** rather than a
   fully-built config, so callers add their own extra keys (staticdir,
   fork, dburl) on top. A single mega-helper with every optional key
   would obscure each test's actual config.
3. **generate_sample_data keeps the `$with_rrds` positional** for now
   (mechanical churn not worth it); named param or split functions is
   the follow-up.
4. **Not factored: Logger::configure, parse_config_from_file
   (generated-conf sites), DBI connect boilerplate** -- variance is real
   and visible; unifying would hide it behind parameters (see Learnings
   #5).

### Rules Added

- **Grep for now-unused imports after moving code into a helper** -- the
  straggler check. Dead imports ship silently otherwise.
- **After an edit touching adjacent import lines, read the block back**
  -- caught a dropped `use File::Path` and a duplicate `use TestUtils`
  this session.
- **Factor by repeated body, not by name** -- byte-identical 6-line
  subs/closures are the signal; repeated one-line calls are not.

### Files Changed

| File | Purpose |
|------|---------|
| `t/lib/TestUtils.pm` | NEW: rglob, setup_test_config, generate_sample_data, mock_update_get_param |
| `t/munin_master_graph.t` | use TestUtils (config, data, mock); drop dead File::Temp + Test::MockModule |
| `t/munin_master_html.t` | same as graph.t |
| `t/munin_master_graph_static.t` | use TestUtils (rglob, config, data, mock); drop File::Find + File::Temp |
| `t/munin_master_html_static.t` | same as graph_static.t; drop dead Test::MockModule + File::Temp |
| `t/munin_master_spec.t` | use TestUtils (rglob, data, mock); drop File::Find + File::Temp + dead require SampleDB |
| `t/munin_master_limits.t` | use TestUtils::generate_sample_data($dir, 0); drop File::Temp |
| `t/munin_master_lifecycle.t` | same as limits.t |
| `t/munin_master_handle_request.t` | same as limits.t |
| `t/munin_master_graph_html_helpers.t` | same as limits.t |

### Test Results

```
perl -c all 10 touched files ................. OK

full make docker-test ....................... PASS 33 files, 490 tests,
    184s wall at shuffle -j4.
    (Graph.pm $tpng/$legend + UpdateWorker 'no such table: node'
    warnings are the pre-existing set proven non-regressions by the
    Session-4 stash-compare.)
```

### Commits

| Commit | Subject |
|--------|---------|
| b69af8d72 | test: factor shared setup into TestUtils |

### Next Steps

Carried forward unchanged from Session 4 (none affected by this
refactor):
1. (optional, scope-cut) graph_static cmdline assertions + 1%
   real-render canary.
2. Reap budget tuning (1s WNOHANG is a guess).
3. CI coverage budget decision.
4. Write contention under real fork=1 load.
5. Pre-existing warnings: Limits.pm:549, Graph.pm:765/869.

New this session:
6. **generate_sample_data's `$with_rrds` positional** -- switch to a
   named param or split into `generate_sample_db` /
   `generate_sample_db_and_rrds` for call-site readability.
7. **Survey the rest of t/ for factoring candidates** -- the survey
   covered the SampleDB/TestState-heavy tests; update_worker/rrdcached/
   spoolfetch tests have their own node-fixture boilerplate that may
   factor similarly (not examined this session).

---

## Session Continuation 6: named builders + DBI connect audit (2026-10-02)

Two follow-ups to Continuation 5, both user-directed. First: replace
`generate_sample_data`'s opaque positional boolean with named
functions. Second: audit the DBI connect boilerplate "from first
principles" -- it was possible some cruft was left over. It was. The
session also produced a new project rule that got applied retroactively
across the whole suite.

### What We Did

1. **Split `generate_sample_data($dir, $with_rrds)` into two named
   functions.** The positional `0` at call sites read as a mystery
   ("generate_sample_db($tmpdir, 0)" -- what does the 0 mean?). Now:
   `generate_sample_db($dir)` (DB-only: limits/lifecycle/handle_request)
   and `generate_sample_db_and_rrds($dir)` (render tests). The second
   delegates to the first, so the SampleDB build is written once. Nine
   call sites updated; no boolean anywhere.

2. **Audited every `DBI->connect` in t/ from first principles.** The
   survey found ~50 copy-pasted connect blocks: 30 in limits.t, 20 in
   spec.t, plus single sites in graph.t, html.t, lifecycle.t,
   update_worker_crud.t, update_worker_dbstate.t. Every one was one of
   exactly two variants (rw / ro). lifecycle.t already solved this
   locally with `dbh_ro()`/`dbh_rw()` subs -- the precedent to
   generalize.

3. **Verified two cruft claims empirically** before acting on them (a
   probe in the dev container, not docs):
   - `AutoCommit => 1` is **redundant**: DBI's default is on. Connect
     with just `{ RaiseError => 1 }` and `{AutoCommit}` is 1.
   - `PrintError` is **moot** alongside `RaiseError => 1`: RaiseError
     dies on bad SQL before PrintError would warn. One site
     (update_worker_dbstate.t) set both -- the redundant one dropped.

4. **Factored the connects into `TestUtils::dbh_ro` / `dbh_rw`.** The
   helpers omit the redundant AutoCommit and document why ("do not
   re-add"). Converted 50 sites via a reviewable perl substitution
   script (`out/refactor_dbi.pl`, reported per-file counts: 30/20, ro/rw
   split) plus the single sites by hand. `my $dbh =` vs bare `$dbh =`
   assignment preserved at every site.

5. **Found one connect that must NOT be factored.** update_groups.t's
   `*Munin::Master::Update::get_dbh` override uses `AutoCommit => 0` --
   which looks exactly like the cruft just removed. It is not: production
   `get_dbh` (Update.pm:128-136) defaults AutoCommit to 0 and honors
   `$is_read_only` / `MUNIN_DB_AUTOCOMMIT`. The override must reproduce
   that contract faithfully; a test helper's connection defaults would
   hide a divergence between the mock and real update runs. Left raw,
   with the reason in a comment.

6. **Swept dead `use DBI;` after the refactor.** With connects in
   TestUtils (which does `require DBI` internally), five files had zero
   `DBI->`/`DBI::` references left. Verified by count before removing.
   crud.t/dbstate.t gained `use TestUtils;` in its place (their connects
   moved to the helper). SampleDB.pm keeps its raw connect -- it is
   *required by* TestUtils (`generate_sample_db` does `require SampleDB`),
   so depending back would be a circular load; also dropped its redundant
   `AutoCommit => 1`.

7. **New project rule, applied retroactively.** User, mid-session: "if
   not using the common method, always explain why in a comment." The
   DBI audit had just surfaced the update_groups.t case where an
   unexplained deviation *looked* like cruft -- exactly the failure mode
   the rule prevents. Swept every config block and connect that bypasses
   a TestUtils helper and added the missing justification (13 comments
   across 12 files), grouped by reason:
   - limits/spec/lifecycle: run limits_main inline (fork=0), render
     nothing -- no tmpldir, no shared-conf parse.
   - handle_request/graph_html_helpers: need dburl + MUNIN_DBURL env,
     which setup_test_config does not set.
   - httpd_graph/update/spoolfetch/rrdcached_integration: generate their
     own conf with the **ephemeral ports** forked test nodes actually
     bound; t/config/munin.conf's fixed ports would collide.
   - update_rrdcached: sets rrdcached_socket/logdir/fork, never parses a
     conf (socket path is per-run).
   - update_groups.t: parses a generated group/host conf from a string to
     exercise config import; the shared conf has no groups.
   - SampleDB.pm / update_groups.t get_dbh: raw connect, reasons above.
   config.t untouched: `Config->instance` there is the subject under
   test, not a setup helper -- no reader would wonder "why not
   setup_test_config."

### What We Learned

#### Technical

1. **Verify attribute defaults empirically before calling them cruft.**
   Both claims (`AutoCommit => 1` redundant, `PrintError` moot) were
   confirmed with a 6-line probe in the dev container, not from memory
   or docs. The probe cost nothing and made the deletions safe.
2. **An unexplained deviation reads as an oversight.** update_groups.t's
   `AutoCommit => 0` was indistinguishable from the cruft being removed
   -- until the comment made the intent legible. Without it, the next
   factoring pass would "clean it up" and silently break the mock's
   fidelity to production.
3. **Layering constrains factoring.** SampleDB.pm cannot use
   TestUtils::dbh_rw because TestUtils requires SampleDB. The dependency
   arrow decides which side owns the raw connect; the comment records
   which side that is.
4. **Named functions beat positional booleans** at every call site. The
   `0` was the kind of magic value that costs a reader a detour to
   decode; the split also made the DB-only vs render split explicit in
   the API.
5. **A factoring pass should keep looking after the first layer.**
   Continuation 5 surveyed "what else can be factored" but stopped at
   the fixture/config layer. The DBI connects -- the largest duplication
   in the suite (50 sites) -- went unnoticed until the user prompted for
   a first-principles audit. "What else" deserves the same scrutiny as
   the original target.

#### Process

1. **User-prompted audits find what self-directed ones miss.** The
   connect boilerplate was invisible to the Continuation-5 survey
   precisely because that survey was framed around the helpers just
   built. A fresh frame ("check for leftover cruft") surfaced it.
2. **Mechanical bulk edits need a reviewable artifact.** The 50-connect
   conversion went through a small perl script that printed per-file
   before/after counts -- the diff review then had a number to check
   against, not just eyeballs.
3. **Rules get applied retroactively, not just recorded.** The "explain
   why" rule was stated mid-session and the sweep happened in the same
   session. A rule recorded for "later" tends to stay later.

### What We Decided

1. **`generate_sample_db` / `generate_sample_db_and_rrds`** replace the
   positional-boolean `generate_sample_data`. Delegation keeps one
   SampleDB build.
2. **`TestUtils::dbh_ro` / `dbh_rw`** own all test sqlite connections.
   Helpers omit redundant `AutoCommit` and document the omission.
3. **update_groups.t's get_dbh override stays raw** -- faithful mock of
   production's AutoCommit-0 contract; comment records why.
4. **SampleDB.pm keeps its raw connect** -- circular-load constraint;
   comment records which side owns it.
5. **Every non-common-method setup carries a "why" comment.** 13
   justifications across 12 files, grouped by reason. config.t exempt
   (subject under test).

### Rules Added

- **Explain deviations in a comment.** When code does not use the
  shared helper for a step, say why at the site. Unexplained deviation
  reads as an oversight and invites a well-meaning cleanup that breaks
  it (the update_groups.t AutoCommit-0 case).
- **Named functions over positional booleans** for helper arguments.
- **Verify attribute/option defaults empirically** before deleting them
  as cruft -- a 6-line probe beats a memory-based claim.

### Files Changed

| File | Purpose |
|------|---------|
| `t/lib/TestUtils.pm` | split generate_sample_data into generate_sample_db + generate_sample_db_and_rrds; add dbh_ro / dbh_rw (no redundant AutoCommit, documented) |
| `t/lib/SampleDB.pm` | keep raw connect (circular-load constraint, commented); drop redundant AutoCommit => 1 |
| `t/munin_master_limits.t` | 30 connects -> dbh_ro/dbh_rw; dead use DBI removed; config deviation commented |
| `t/munin_master_spec.t` | 20 connects -> dbh_ro/dbh_rw; dead use DBI removed; config deviation commented |
| `t/munin_master_graph.t`, `t/munin_master_html.t` | single connect -> dbh_rw; dead use DBI removed; call sites renamed |
| `t/munin_master_lifecycle.t` | dbh_ro/dbh_rw subs delegate to TestUtils; dead use DBI removed; config deviation commented |
| `t/munin_master_update_worker_crud.t`, `t/munin_master_update_worker_dbstate.t` | connect -> dbh_rw (dbstate: dropped moot PrintError); use DBI -> use TestUtils |
| `t/munin_master_handle_request.t`, `t/munin_master_graph_html_helpers.t`, `t/munin_master_graph_static.t`, `t/munin_master_html_static.t` | call sites renamed to generate_sample_db(_and_rrds); dburl config deviation commented |
| `t/munin_master_httpd_graph.t`, `t/munin_master_update.t`, `t/munin_master_update_spoolfetch.t`, `t/munin_master_update_rrdcached_integration.t` | generated-conf deviation commented (ephemeral ports) |
| `t/munin_master_update_rrdcached.t` | config deviation commented (per-run socket path) |
| `t/munin_master_update_groups.t` | get_dbh override: AutoCommit-0 fidelity commented; conf-from-string deviation commented |

### Test Results

```
perl -c all touched files ................. OK (12 files)

full make docker-test (after commit 1) .... PASS 33 files, 490 tests,
    222s wall at shuffle -j4.
full make docker-test (after commit 2) .... PASS 33 files, 490 tests,
    227s wall at shuffle -j4.

DBI audit totals: 50 connects factored (limits.t 30 = 14 ro + 16 rw;
    spec.t 20 = 9 ro + 11 rw), 5 dead 'use DBI' removed, 1 faithful
    mock left raw with justification, 13 why-comments across 12 files.
```

### Commits

| Commit | Subject |
|--------|---------|
| 2ce1188b9 | test: name TestUtils fixture builders; factor DBI connects |
| 2308d4ab2 | test: justify every non-common-method setup in a comment |

### Next Steps

Carried forward unchanged (none affected by this session):
1. (optional, scope-cut) graph_static cmdline assertions + 1%
   real-render canary.
2. Reap budget tuning (1s WNOHANG is a guess).
3. CI coverage budget decision.
4. Write contention under real fork=1 load.
5. Pre-existing warnings: Limits.pm:549, Graph.pm:765/869.

Status updates:
6. ~~generate_sample_data's `$with_rrds` positional~~ -- **done** (this
   session, split into named functions).
7. ~~Survey the rest of t/ for factoring candidates~~ -- **done**
   across Continuations 6-7: DBI connects factored, config deviations
   documented, and the generated-conf blocks now live in
   `TestUtils::generate_test_conf` (see Continuation 7).

---

## Session Continuation 7: generate_test_conf -- the flagged next pass (2026-10-02)

Continuation 6's Next Steps named the candidate explicitly: the
generated-conf tests "each write near-identical conf-generation blocks --
a `generate_test_conf($dir, \%nodes)` helper is the obvious candidate."
This session is that pass, and it is deliberately small.

### What We Did

1. **Compared all four conf-generation blocks before touching anything.**
   Extracted each block (`awk` from `my $conf_file` to `close $fh`) and
   ran `diff` pairwise rather than trusting the eyeball read:
   - httpd_graph.t == update.t == spoolfetch.t -- **byte-identical**
     (28 lines: same four dirs under `$temp_dir`, same five-node layout,
     same ephemeral `$ports` from `get_free_ports(3)`).
   - update_rrdcached_integration.t -- **genuinely different**: separate
     `html`/`run` subdirs, a `rrdcached_socket` line, and loop-generated
     `group-$i`/`host-$i` nodes instead of the fixed five.

2. **Added `TestUtils::generate_test_conf($dir, $ports)`** for the three
   identical cases. The helper owns the filehandle (open/print/close
   moves inside) and returns the conf path. Its pod records *why*
   rrdcached_integration is excluded -- folding it in would need an
   option bag (dir overrides, extra key, node-generator callback) that
   obscures more than it dedups. That is the Continuation-5
   `parse_config_from_file` lesson applied to a second case.

3. **Converted the three callers** to a one-liner each; added
   `use TestUtils;` to the three files (none imported it). Verified no
   leftover `$fh` references -- the helper owns the handle now. The
   `# Not setup_test_config()` comments stayed: the helper is *not*
   `setup_test_config`, the tests still generate their own conf with
   ephemeral ports, so the justification remains true.

### What We Learned

1. **diff beats the eyeball for "is this byte-identical?"** Three blocks
   that looked identical at a glance were confirmed identical by
   extraction + `diff` before any edit. If they had differed in
   whitespace or a stray key, the bulk edit would have silently
   picked one variant.
2. **A helper named in a Next Steps list gets done; an unnamed one
   lingers.** Continuation 6 wrote down `generate_test_conf($dir,
   \%nodes)` as the candidate with its reason. This session was a
   straight execution of that note -- the documentation paid for itself
   as a handoff, even to the same person a session later.
3. **The option-bag test applies per-helper, not per-file.**
   rrdcached_integration sits in the same *file family* as the three
   converted tests but has different *needs*; the unit of factoring is
   the identical block, not the test file.

### What We Decided

1. **`generate_test_conf($dir, $ports)` takes a ports arrayref**, not a
   node list -- the three identical blocks share one fixed five-node
   layout parameterized only by port. A `\%nodes` structure would have
   been speculative generality for a shape no caller uses.
2. **rrdcached_integration stays unconverted**, with the exclusion
   documented in the helper's pod (not just in the caller), so the next
   person meets the reason at the point of temptation.

### Files Changed

| File | Purpose |
|------|---------|
| `t/lib/TestUtils.pm` | add generate_test_conf($dir, $ports); pod records the rrdcached exclusion |
| `t/munin_master_httpd_graph.t` | 28-line conf block -> one-liner; use TestUtils added |
| `t/munin_master_update.t` | same |
| `t/munin_master_update_spoolfetch.t` | same |

### Test Results

```
perl -c all 4 touched files ............... OK

full make docker-test ..................... PASS 33 files, 490 tests,
    181s wall at shuffle -j4.
    (Node::_node_write_single redefinition warning in node_multigraph.t
    observed this run: PRE-EXISTING -- node_multigraph.t / Node.pm are
    not in this diff. Same family as the other proven non-regressions;
    not investigated this session.)
```

### Commits

| Commit | Subject |
|--------|---------|
| dcd0be786 | test: factor integration-test conf generation into TestUtils |

### Next Steps

Carried forward unchanged:
1. (optional, scope-cut) graph_static cmdline assertions + 1%
   real-render canary.
2. Reap budget tuning (1s WNOHANG is a guess).
3. CI coverage budget decision.
4. Write contention under real fork=1 load.

Pre-existing warnings, now four known sets (all proven non-regressions
by diff-exclusion or stash-compare, none investigated):
5. Limits.pm:549 `$dbdir` undef in `_compute_cdef_value`.
6. Graph.pm:765 `$tpng` / 869 `$legend` uninitialized in DEBUG paths.
7. **Node::_node_write_single / _node_read redefinition** in
   node_multigraph.t (lines 44/49) -- new observation this session;
   the test redefines Node subs that are already loaded.
8. update_worker_crud.t `no such table: node` (DBD::SQLite prepare
   noise around schema creation).

**Factoring survey is now closed** -- every repeated block in t/ that
was surveyed has been either factored into TestUtils or justified in a
comment. Remaining t/ work is behavioral (the canary, the warnings),
not structural.

---

## Session Continuation 8: Node sub redefinition warning (2026-10-02)

Small session. Picked up item 7 from the pre-existing-warnings list:
`Subroutine Munin::Master::Node::_node_write_single redefined` in
node_multigraph.t. Investigated, fixed, verified.

### What We Did

1. **Read the cause.** `create_mock_node` installed two Node subs
   (`*_node_write_single`, `*_node_read`) via raw glob assignment on
   **every call** -- over subs already loaded by `require
   Munin::Master::Node`. Seven nodes per run meant the warning fired
   seven times.

2. **First fix reduced the noise but did not eliminate it.** Moved the
   install out of `create_mock_node` into a one-time load-time block.
   The warning dropped from 7x to 1x but persisted -- because the
   overwrite itself is what Perl warns about, regardless of frequency.

3. **Second fix eliminated it.** Added `no warnings 'redefine';` in the
   scoped install block. The overwrite is intentional (mocking the real
   subs for a unit test), so suppressing the warning is correct, not
   masking -- and the comment says so.

4. **Verified the once-installed shared subs are sound.** Both mocked
   subs read only from `$self` (no closure over `create_mock_node`'s
   lexicals), so per-call re-installation was pure redundancy. Each
   `create_mock_node` call blesses a *new* hash carrying its own
   `_config_lines`, so the 7 tests still validate the shared subs
   against 7 different canned configs -- not passing vacuously.

5. **Straggler swept.** Dropped the dead `use Test::MockModule;` --
   confirmed unused in the committed version too (pre-existing, not
   introduced here; the straggler discipline applies to imports that
   outlive their use, wherever they came from).

### What We Learned

1. **"Redefinition" warnings have two shapes: accidental and
   intentional.** Accidental ones mean a load-order bug; intentional
   ones (test mocks replacing real subs) are fixed by *scoping the
   suppression*, not by frequency reduction. Moving the install out of
   the per-node helper addressed redundancy but not the warning -- the
   pragma addressed the warning. Both were worth doing; neither alone
   was sufficient.
2. **Per-instance data survives shared subs when state lives on
   `$self`.** The safety of "install once" hinged on the mocked subs
   closing over nothing. Had they closed over `create_mock_node`'s
   lexicals, one install would have frozen the first node's config across
   all seven. Worth checking closure capture before deduplicating any
   install-time mock.

### What We Decided

1. **`no warnings 'redefine'` scoped to the install block**, not file-
   wide -- limits the suppression to the one intentional overwrite.
2. **`create_mock_node` keeps its name and role** (bless the per-instance
   hash); only the redundant install moved out.

### Files Changed

| File | Purpose |
|------|---------|
| `t/munin_master_node_multigraph.t` | install the two Node mocks once at load with `no warnings 'redefine'`; create_mock_node now only blesses the hash; dead `use Test::MockModule` removed |

### Test Results

```
node_multigraph.t solo ................... ok 7 tests, 1s; redefinition
    warning GONE (was 7x per run).

full make docker-test ..................... PASS 33 files, 490 tests,
    227s wall at shuffle -j4.
```

### Commits

| Commit | Subject |
|--------|---------|
| a398da8e5 | test: fix Node sub redefinition warning in node_multigraph.t |

### Next Steps

Carried forward unchanged:
1. (optional, scope-cut) graph_static cmdline assertions + 1%
   real-render canary.
2. Reap budget tuning (1s WNOHANG is a guess).
3. CI coverage budget decision.
4. Write contention under real fork=1 load.

Pre-existing warnings -- **three sets remain** (item 7 now fixed):
5. Limits.pm:549 `$dbdir` undef in `_compute_cdef_value`.
6. Graph.pm:765 `$tpng` / 869 `$legend` uninitialized in DEBUG paths.
7. ~~Node::_node_write_single / _node_read redefinition~~ -- **fixed**
   (this session).
8. update_worker_crud.t `no such table: node` (DBD::SQLite prepare
   noise around schema creation).

---

## Session Continuation 9: jquery unminification + untracked-file archaeology (2026-10-02)

Small session, two parts: a directive correction, and a swap of the
minified jQuery for the unminified build. The investigation into two
mystery untracked files turned up an unmerged branch that had already
made the same change a year and a half ago.

### What We Did

1. **Revoked Working Directive 1.** The user removed the bash-output
   plugin ("I removed the plugin, so please redo the redirects"). The
   AGENTS.md debug rule is back in force: redirect to `out/*.out` /
   `out/*.err` files and read/grep them. Directives 2-6 stand. Recorded
   in the log's directive list; committed as 3f9fbf5fd.

2. **Investigated two untracked files** (`web/static/js/jquery-3.7.1.js`
   and `contrib/plugin-gallery/www/static/js/jquery-3.7.1.js`, both dated
   Sep 30 23:09). No source reference pointed at them; only the
   `.min.js` twins were tracked. The untracked files were byte-identical
   (sha256) to files added by commit `5adbd4eea` "autocommit"
   (2025-04-14) on the **unmerged** branch
   `breadcrumb-19d94a149077ff68ffbb37364d0ee82c59fa6f2d` -- which had
   already done exactly the change the user then requested: delete both
   `.min.js`, add the unminified files, point both templates at them.
   That branch carries 2655 commits not on `feat/url-fk-schema` (it
   tracks a newer/different line of development; only the second breadcrumb
   branch remains unexamined).

3. **Answered "why 2 versions of jquery in the main site?" with
   history archaeology** (`git log --all --oneline --name-only --
   'web/**'`): the main site never had two live versions. Timeline:
   jquery-1.8.3 + lazyload plugin (pre-2021) -> jquery-1.12.4 (added
   2021-02-06 `d541735c0`/`2d0c0abf6`) -> jquery-3.7.1 minified-only
   (2023-09-13 `435e12ac4` deleted the 1.12.4 sources and shipped only
   `.min.js`). The old versions exist only in git history -- zero copies
   on disk. The plugin-gallery carries its own copy **by design**: it is
   a standalone static export with its own DocumentRoot
   (`gallery-build.sh` rsyncs `contrib/plugin-gallery/www/static` into
   the target dir), so its vendored assets are not duplication.

4. **Swapped minified -> unminified.** Verified the on-disk file is
   genuine jQuery v3.7.1 (MIT banner, dated 2023-08-28). `git rm` both
   `.min.js`, `git add` both unminified files, updated the only two
   references repo-wide (`web/templates/partial/head.tmpl:9`,
   `contrib/plugin-gallery/static/gallery-footer.html:7`) via edit.
   User's rationale: "we are not a high load website anyway" -- the
   readable source is worth more than ~200KB saved.

5. **Synced the sandbox install tree.** `sandbox/` is the untracked
   install prefix used by the docker image; its copies of the js dir and
   templates were stale (old min.js, old head.tmpl). Install makes those
   files read-only -- `chmod u+w` before copying, restore `a-w` after.
   The install does not self-clean: the deleted min.js had to be removed
   by hand.

6. **Regenerated MANIFEST from scratch.** The untracked generated
   MANIFEST still listed the deleted min.js after `./Build manifest` --
   that action is **additive only** (adds missing files, never prunes
   gone ones). `rm MANIFEST MANIFEST.bak && perl Build.PL` produced a
   clean one (only unminified entries). Echoes the Session-3 lesson:
   MANIFEST is stateful; verify from fresh generation, not a re-run.

7. **Validation:** full `make docker-test` -- **PASS, 33 files, 490
   tests, 188s** wall at shuffle -j4. Visible warnings were the known
   pre-existing sets (Graph.pm `$tpng`/`$legend`, UpdateWorker
   `no such table: node`, HTML.pm `$tmpldir` in handle_request.t) --
   none touched by this change. Working tree clean after commit.

### What We Learned

1. **Untracked files in a mostly-clean tree deserve a "why are you
   here" investigation before deletion.** This one led to the breadcrumb
   branch discovery -- the change had already been made, tested nowhere,
   and sat unmerged for 18 months. Deleting blindly would have been
   fine here, but the investigation also answered the user's "2
   versions?" question with evidence instead of assertion.
2. **`git log --all` shows history across every ref.** Files deleted
   from HEAD still appear in `--all --name-only` listings -- that is
   exactly how the jquery-1.12.4.js question ("is that still around?")
   got answered: lifecycle via `--diff-filter=AD`, zero copies on disk.
3. **`./Build manifest` is additive only.** Stale entries for deleted
   files survive it; only a fresh generation (rm + Build.PL) prunes.
4. **Install trees (sandbox/) are read-only and don't self-clean.**
   Reinstalling copies changed files but leaves orphans; sync or
   reinstall from scratch after removing source files.
5. **The gallery's separate jquery copy is by design, not drift.**
   Standalone static export, own DocumentRoot -- factoring it into the
   main site's copy would couple two independently deployed artifacts.

### What We Decided

1. **Serve unminified jQuery 3.7.1 everywhere** (both the main web UI
   and the standalone gallery); references updated, not removed -- the
   scripts are still needed.
2. **Redo the change on this branch rather than merge from the
   breadcrumb branch.** 2655 commits of divergence; cherry-picking an
   "autocommit" tip is riskier than replaying a 6-file swap whose
   content was verified identical (sha256) to what we shipped.
3. **Directive list updated in place** -- directive 1 marked REVOKED
   with the reason and date; a future session reading the log header
   sees the current rule, not a stale one.

### Files Changed

| File | Purpose |
|------|---------|
| `web/static/js/jquery-3.7.1.min.js` | removed (git rm) |
| `web/static/js/jquery-3.7.1.js` | added -- the served build now |
| `contrib/plugin-gallery/www/static/js/jquery-3.7.1.min.js` | removed (git rm) |
| `contrib/plugin-gallery/www/static/js/jquery-3.7.1.js` | added |
| `web/templates/partial/head.tmpl` | script src -> jquery-3.7.1.js |
| `contrib/plugin-gallery/static/gallery-footer.html` | script src -> jquery-3.7.1.js |
| `sandbox/etc/static/js/`, `sandbox/etc/templates/` | untracked install tree synced (rm min, copy js + tmpl) |
| `MANIFEST` | untracked; regenerated fresh (min.js entries gone) |
| `mission_log/2026-10-01_test_suite_parallelism.md` | directive 1 revoked; this session logged |

### Commits

| Commit | Subject |
|--------|---------|
| 3f9fbf5fd | docs: revoke bash-output-plugin directive; redirects back in force |
| 225ff77ec | web: drop minified jquery; serve unminified 3.7.1 |

### Next Steps

Carried forward unchanged:
1. (optional, scope-cut) graph_static cmdline assertions + 1%
   real-render canary.
2. Reap budget tuning (1s WNOHANG is a guess).
3. CI coverage budget decision.
4. Write contention under real fork=1 load.
5. Pre-existing warnings (3 sets): Limits.pm:549, Graph.pm:765/869,
   update_worker_crud.t `no such table: node`.

New this session:
6. **Second breadcrumb branch unexamined** --
   `breadcrumb-b41c2547464aa6cf01faa9f396d093efd46c80c7` may carry more
   unmerged work; review or delete both breadcrumb branches once their
   provenance is confirmed.
