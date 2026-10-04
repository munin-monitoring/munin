# Mission Log: Covered-Suite Parallel Perf -- Why CI "Parallel" Is Slower

**Date:** 2026-10-04
**Context:** CI's matrix shows the "parallel" test configurations taking
longer than "serial", which looked like a paradox ("4 jobs should be at
least 2x faster"). No `gh` access in this environment, so the CI
comparison was reproduced and instrumented locally with the exact
`make docker-cover` command shapes. This log records the mechanism,
the measurements, and the dead ends.

---

## What We Did

### Part 0: What CI actually compares (the premise correction)

`.github/workflows/build-n-test.yml`, test matrix:

```
serial-sqlite:   JOBS=4 FORK=0 DBDRIVER=sqlite
parallel-sqlite: JOBS=4 FORK=1 DBDRIVER=sqlite
parallel-pgsql:  JOBS=4 FORK=1 DBDRIVER=pg
```

**All three jobs run `prove -j4`.** The serial/parallel labels are the
`MUNIN_TEST_FORK` axis -- whether the munin *master* forks worker
processes -- not prove parallelism. There is no -j1 vs -j4 comparison
anywhere in CI. The user's "4 jobs vs 1 job" premise described no CI
comparison; the real variable is the master's fork mode.

### Part 1: Source archaeology -- what FORK=1 changes

- `t/lib/TestUtils.pm` `fork_mode()`: `MUNIN_TEST_FORK` -> `$config->{fork}`;
  eight test files consume it.
- `lib/Munin/Master/Update.pm` `_run_workers`: `Parallel::ForkManager`,
  `$max_processes = 0 unless get_param('fork', $dbh)`.
- **PFM semantics verified in source** (`Parallel/ForkManager.pm::start`):
  `if ($s->{max_proc}) { fork... }` -- with `max_proc == 0` it takes the
  explicit *"non-forking mode"* branch (`return 0`, worker runs
  in-process). So FORK=0 is genuinely serial at the worker level.
- Fork census: `t/lib/SampleDB.pm` = 5 hosts x 5 services = **25 workers
  per update cycle**. Update-family tests run >= 8 master cycles
  (update.t x2, spoolfetch x3, httpd_graph x1, rrdcached_integration x2,
  plus rrdcached.t and limits/lifecycle/spec paths) -> **>= 200
  fork-without-exec children** in FORK=1. Each child inherits
  Devel::Cover and runs `exit` -> END blocks.

### Part 2: Devel::Cover 1.38 fork semantics (Debian split, no fork guard)

Dead end first: `grep fork|pid` over the container's `Cover.pm` returned
**zero hits**. Debian's package splits collection into
`Devel/Cover/*.pm`; the main module is the API surface. Extracted
`Cover.pm`, `DB.pm`, `Structure.pm`, `Digests.pm`, `Util.pm` with
`cat > out/...` and read them locally (faster and diff-able vs fighting
grep quoting inside `docker run sh -c`).

Findings, all source-cited:

- `Cover.pm::last_end`: `report() if $Initialised` -- **unconditional;
  zero pid checks anywhere in Cover.pm**. There is no fork guard.
- `report()` computes the run name at EXIT with a fresh pid:
  `my $run = time . ".$$." . sprintf "%05d", rand 2 ** 16;` -- so every
  forked child writes its **own** `runs/<ts>.<pid>.<rand>/` dir,
  containing a full serialization of everything that process covered.
- `DB.pm::write` then does `$self->{structure}->write($self->{base})` --
  `Structure.pm::write` rewrites **every covered file** into the shared
  base db on every process exit. The code's own TODO admits it:
  *"determine if Structure has changed to save writing it"*.
- `$Digests->write` (`DB/Digests.pm`): unlocked read-modify-write of the
  single shared `cover_db/digests` file.

Conclusion: the coverage db is a **shared-write structure**. N
instrumented process exits = N full run serializations + N storms of
structure file writes (temp + rename, no locking) + N digests
read-modify-writes, all aimed at one base db -- while up to 4 CI jobs'
processes do this concurrently.

### Part 3: The fork-tax micro-bench (the decisive measurement)

`out/fork_cover_bench.pl`: loads real Munin modules (`Master::Config`,
`Master::Update`, `Master::UpdateWorker` -- so each child's `report()`
serializes the same payload the suite's children would), forks N
children that touch loaded code and exit. Plain vs covered, in the dev
container (`out/run_forktax_bench.sh`):

| forks | plain wall | covered wall | per child |
|------:|-----------:|-------------:|----------:|
| 0     | 0.00s      | 0.00s        | --        |
| 5     | 0.12s      | 22.2s        | ~4.4s     |
| 25    | 0.50s      | 112.2s       | ~4.5s     |
| 100   | 2.06s      | OOM (see below) | linear |

Covered run dirs after each run = **N + 1** -- empirical confirmation
that every child ran the full `report()` (no fork guard). Plain cost
per child ~20ms; covered ~4.4s: a **220x fixed cost per process**,
perfectly linear.

The N=100 covered point died silently: 100 concurrent covered children
exhausted the host's 3.9GB RAM (no output line at all -- detected by
absence, after `pgrep` showed nothing alive). CI runners have 16GB, so
this is a local artifact; the CPU oversubscription story is identical
on both.

### Part 4: Instrumented local CI reproduction

`out/run_cover.sh` + `out/ps_sampler.sh`: runs the exact CI command
shape (`make docker-cover COVER_REPORT=0 JOBS=4 FORK=... DBDRIVER=sqlite`),
logs prove output to `out/cover_<label>.out`, snapshots
`cover_db/runs` census + sizes to `out/coverdb_<label>.stats`, tars the
whole cover_db, and samples host `ps` (procs + rss) every 2s.

**ciser = FORK=0, JOBS=4, covered (CI serial-sqlite shape):**

```
rc=0  wall_secs=1009  files=37  sum(per-file wall)=3878s
runs_entries=206  unique_pids=151  cover_db=2.9MB
peak_procs=30  peak_rss=1.3GB
```

Average concurrency 3878/1009 = **3.84 of 4 cores** -- `-j4` does keep
the box busy. But the giants are internally parallel (each spawns node
servers, rrdtool renders via Devel::Cover's own `sys` forks), so they
burn 2-3 cores *each* while running:

| file (covered, -j4, FORK=0) | wall   | CPU    |
|-----------------------------|-------:|-------:|
| munin_master_spec.t         | 588.7s | 894.5s |
| munin_master_graph.t        | 380.9s | 1132.6s|
| munin_master_schema_migration.t | 378.8s | 1083.1s |
| munin_master_html.t         | 315.2s | 744.4s |
| munin_migrate_rrd.t         | 273.2s | 857.1s |
| munin_master_limits.t       | 200.3s | 245.9s |

Two concurrent covered giants demand 6-9 cores on a 4-core box -> each
stretches ~2x vs an idle box. Makespan pins to the chain: **spec.t's
589s = 58% of the total 1009s wall**.

### Part 5: The free -j1 covered datapoint (a mistake, kept)

The first `run_cover.sh` launch forgot the `TESTS=` override, so it ran
the **whole suite covered at -j1** (FORK=0) -- killed ~19 minutes in
once noticed. Not wasted: it is the only covered -j1 datapoint, and
joined against ciser (-j4, identical config otherwise) it is a clean
per-file A/B:

| file | covered -j1 | covered -j4 | -j4 vs -j1 |
|------|------------:|------------:|-----------:|
| spec.t            | 274.8s | 588.7s | **2.1x slower** |
| limits_cdef.t     | 15.3s  | 89.0s  | **5.8x slower** |
| httpd_html.t      | 16.1s  | 55.3s  | 3.4x slower |
| handle_request.t  | 18.5s  | 29.6s  | 1.6x slower |
| fk_enforcement.t  | 15.8s  | 25.7s  | 1.6x slower |
| timeout.t         | 10.3s  | 15.5s  | 1.5x slower |
| defaults.t        | 2.3s   | 3.4s   | 1.5x slower |

**7 of 7 common files slower at -j4.** Aggregate covered -j4 vs covered
-j1 total is unmeasured (the -j1 run was killed); structurally it lands
around 1.5-2.5x -- throughput survives, per-file latency uniformly does
not.

### Part 6: cifor = FORK=1 (CI parallel-sqlite shape) in flight

Started after ciser; 12/37 files done at time of writing. Partial
per-file numbers are **shuffle noise**, not signal -- each file's wall
depends on which giants shared its slot window (html.t is so far
*faster* under FORK=1; httpd_html.t 2x slower). The trustworthy
comparisons are the totals and the exit-count delta
(`out/compare_ci.sh` is ready for when it lands). Expected: wall >
1009s from >= 200 extra children x ~4.4s exit tax (~+880 CPU-s ~ +220s
wall minimum) landing on already-saturated cores, plus up to 4 jobs x
16 workers = 64 concurrent covered processes.

---

## What We Learned

### Technical

1. **CI config names are not semantics.** "serial"/"parallel" in the
   matrix mean the FORK axis; all jobs run `-j4`. Read the make_args,
   not the label.
2. **The -j model, with numbers:** `T(j) >= max(sum CPU / j, longest
   chain) + contention inflation`. Plain suite (2026-10-01 session):
   529s/-j1 -> 274s/-j4 = 1.93x, and -j3 ~= -j4 -> chain-bound, not
   slot-bound. The "at least 2x" expectation is essentially met for
   plain runs -- and only just, since `prove --shuffle` is random, not
   LPT (stacking the two 100s+ giants back-to-back costs the win).
3. **Under Devel::Cover at -j4, per-file latency regresses vs an idle
   box** (7/7 measured, up to 5.8x) because the giants are themselves
   multi-core (2-3 cores each); makespan pins to the longest chain
   (spec.t = 58% of total wall).
4. **Devel::Cover 1.38 has no fork guard; every forked child pays a
   full coverage shutdown** -- own runs dir + full structure rewrite +
   digests into the shared base db. Measured ~4.4s per child with Munin
   modules loaded, linear, vs ~20ms plain.
5. **The first-principles punchline:** forking wins iff per-child
   useful work >> per-child fixed cost. Coverage inflates the fixed
   cost 220x while useful work (one service fetch on a 5-service
   fixture) stays milliseconds -- so FORK=1, free in production (plain
   suite: 206s vs 197s, 2026-10-01 session), is a net *loss* under
   instrumentation: >= 200 children x 4.4s ~= +880 CPU-s on 4 cores.
   The "parallel" CI config is slower than "serial" because it added
   load, not throughput.
6. **The coverage db is a shared-write structure.** Every process exit
   rewrites structure/* into the base (no change detection -- the code
   says so) and read-modify-writes digests, unlocked. Under `-j4`
   matrix jobs this storms one directory.
7. **Instrumentation gotchas:** Devel::Cover's per-process messages
   ("Writing coverage database...") never reach prove logs -- the TAP
   harness swallows them; the exit census comes from `cover_db/runs`
   dir names (`<ts>.<pid>.<rand>`) instead. Local host has 3.9GB vs
   CI's 16GB: CPU oversubscription (4 vCPU) is identical on both, RAM
   headroom is not -- local fork-mode walls are pessimistic vs CI.

### Process

1. **Bench first, reproduce second.** The 3-minute micro-bench answered
   the "why" decisively; the ~1 hour of covered suite runs quantified
   it. The order was backwards -- the bench should have preceded the
   full runs.
2. **First-principles source reading settles what labels obscure.** Two
   file reads (`PFM::start`, `Cover.pm::last_end`) removed the
   paradox before any measurement ran.
3. **`pkill -f` self-match:** the pattern was text inside my own
   `bash -c` command line, so pkill SIGTERMed the shell running it
   (exit 143) before reaching the target. Also learned `docker` here is
   podman. Kill by explicit PID.
4. **Accidental runs can be data.** The forgotten `TESTS=` override
   produced the covered -j1 vs -j4 A/B for free.
5. **A/B discipline at -j4 under contention:** per-file walls are
   shuffle-dependent (cifor's partial data flips signs between files).
   Totals and mechanism metrics (exit counts, CPU sums, run-dir
   census) are the trustworthy signals.

---

## What We Decided

1. **The CI inversion is expected behavior, not a bug.** FORK=1 under
   Devel::Cover pays a measured ~4.4s exit tax per forked child across
   >= 200 children; FORK=0 pays it once per test process. No production
   code changed this session.
2. **Two candidate levers, both recorded pending measurement:**
   - `prove --state=slow` (LPT scheduling) for the CI chain term --
     designed and dropped in the 2026-10-01 session for local shuffle
     benefits; CI-only application would shrink the spec.t chain.
   - Clear `$Devel::Cover::Initialised` in the worker child right after
     `$pm->start` (guarded by `PERL5OPT =~ /Devel::Cover/`):
     `last_end` checks `$Initialised`, so children would skip
     `report()` entirely. Test-side only, zero production semantics.
3. This log ships with cifor totals pending; a Session 2 append records
   them when the run lands.

---

## Rules Added

- **Kill by explicit PID** when your `pkill -f` pattern appears in your
  own command line (self-match SIGTERM).
- **For -j4 A/B comparisons, compare totals + mechanism metrics, never
  per-file walls** -- shuffle makes per-file walls schedule noise.
- **Devel::Cover semantics: probe, never trust docs or memory**
  (extends the 2026-10-01 rule). The run-name construction
  (`time.$$rand` at exit) is itself the proof of per-child writes.
- **Before extrapolating a linear per-process cost to large N, check
  RAM** -- covered children OOM'd at N=100 on a 3.9GB host, silently.
- **CI config names are not semantics; read the make_args.**

---

## What We'd Do Differently

1. **Micro-bench before full reproduction.** Mechanism in 3 minutes
   vs ~1 hour of covered suite wall time.
2. **Fix the runner's `TESTS` handling before launching** -- the
   accidental -j1 run cost ~20 minutes (though it yielded the A/B).
3. **Sampler should record memory pressure + swap, not just rss sum** --
   the OOM was detected by absent output, not by the sampler.
4. **Record PIDs at launch, kill by PID** -- no more `pkill -f`.
5. **Extract perl modules with `cat > out/...` and read locally** at
   the first grep failure instead of fighting shell quoting inside
   `docker run sh -c` (three rounds lost to that).

---

## Files Changed

No production code. Instrumentation under `out/` (gitignored,
rerunnable):

| File | Purpose |
|------|---------|
| `out/run_cover.sh` | Run one covered CI config with wall/stats/tarball instrumentation |
| `out/ps_sampler.sh` | Host-side process/rss sampler (2s interval) |
| `out/fork_cover_bench.pl` | Per-forked-child Devel::Cover exit-tax micro-bench |
| `out/run_forktax_bench.sh` | Bench driver (plain vs covered, N=0/5/25/100) |
| `out/compare_ci.sh` | ciser vs cifor: totals, per-file deltas, exit counts |
| `out/cover_ciser.out` | prove log, FORK=0 covered run (full) |
| `out/cover_cifor.out` | prove log, FORK=1 covered run (in flight) |
| `out/cover_serial.out` | prove log, accidental -j1 covered run (partial, killed) |
| `out/bench_forktax.out` | Bench results |
| `out/ps_ciser.log`, `out/ps_cifor.log` | Process/rss samples |
| `out/coverdb_ciser.stats`, `out/coverdb_ciser.tgz` | Exit census + full cover_db snapshot |

---

## Test Results / Benchmarks

All numbers from this session unless noted; plain-suite numbers from
the 2026-10-01 session.

**Fork-tax micro-bench** (real Munin modules loaded, dev container):

| forks | plain | covered | run dirs |
|------:|------:|--------:|---------:|
| 0  | 0.00s  | 0.00s   | 1  |
| 5  | 0.12s  | 22.2s   | 6  |
| 25 | 0.50s  | 112.2s  | 26 |
| 100| 2.06s  | OOM     | -- |

**Covered suite, exact CI shape, local (4 cores, 3.9GB):**

```
ciser (FORK=0 JOBS=4): rc=0 wall=1009s  37 files  Sigma wall=3878s
                       runs_entries=206  peak 30 procs / 1.3GB
cifor (FORK=1 JOBS=4): in flight at time of writing (12/37 files)
```

**Covered per-file, -j1 vs -j4, FORK=0:** see Part 5 table -- 7/7
files slower at -j4; spec.t 274.8s -> 588.7s.

**Plain suite (2026-10-01):** -j1 529s/498 CPU; -j3 269s/669;
-j4 274s/654. FORK=1 206s vs FORK=0 197s (sqlite, plain).

---

## Next Steps

1. **cifor lands** -> run `out/compare_ci.sh`; append Session 2 with
   the wall delta and exit-count delta (expect exits >> 206). Attribute
   FORK=0's ~169 non-test exits (Devel::Cover `sys` forks vs test-side
   fork-without-exec) while the tarball is fresh.
2. **Measure the two levers before adopting either:** micro-bench the
   `Initialised=0` hook (25 children, expect ~0.5s not 112s); trial
   `--state=slow` on one CI config.
3. Optional: full covered -j1 FORK=0 run to pin the aggregate covered
   -j4 speedup (per-file regression already proven; totals remain an
   estimate).
4. When reading cifor's local wall, remember 3.9GB local vs 16GB CI --
   expect CI's FORK=1 penalty to be somewhat smaller than local, with
   the same mechanism underneath.
