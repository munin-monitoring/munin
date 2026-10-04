# Mission Log: Offline Schema Migration (munin-upgrade-db)

**Date:** 2026-10-03
**Context:** Implement `specs/01_OFFLINE_SCHEMA_MIGRATION.md`: move every
schema change out of the runtime hot path into a dedicated offline tool,
`munin-upgrade-db`, and make every runtime consumer verify the schema
version at `get_dbh` and die loudly on mismatch.

---

## What We Did

### Phase 1: The shared schema module

`lib/Munin/Master/Schema.pm` is the single source of truth. The key
structural decision: the DDL is **rendered from one canonical data
structure** (`@TABLES`: columns with types/options, named indexes,
table-level PKs, CHECK expressions, inline FKs), and the introspection
expectations (`expected_schema`) are derived from the *same* structure.
The tool's fingerprint verification and the DDL cannot drift, because
they are two renderings of one array.

Public surface: `create_schema`, `record`, `detect`, `introspect`,
`migrate_v0_to_v1`, `verify`, plus the diff/expected/pending helpers the
tool composes. `version_history` is created by `record()` on demand --
the spec says `create_schema` must not create it "so every write to the
audit trail is deliberate", which implies `record()` owns its DDL.

The v0 golden fixture (`t/lib/v0_schema.sql`) was **generated** from the
canonical specs (minus `ds_rrd`, minus `ds.deleted`), not hand-typed:
test 1 compares the upgraded fixture against a fresh bootstrap, so drift
between the golden file and the module fails loudly instead of silently.

### Phase 2: The tool

`script/munin-upgrade-db` implements the spec's algorithm: detect ->
fresh/unversioned/versioned-branches, strict acceptance check (core
tables + unknown tables + extra-column classification), stepwise
migration inside one transaction, fingerprint verify, one audit row per
applied step, commit. `--dry-run` reuses the *real* code path: every
migration statement goes through a `_do()` helper that records into
`$dbh->{private_munin_sql_log}` (DBI's reserved `private_` namespace);
the transaction is rolled back after printing. No second implementation
of the migration to keep in sync.

`--yolo` is the ladder from the spec: exact adoption, additive repair,
data reconciliation, hard floor. Refusals that hold in *both* modes
(constrained extra columns, unrepairable PK/type divergences) are
checked before any write, so a refused database stays byte-identical.
The audit comment for a yolo run is one fat narrative built from what
actually executed -- structural actions, migration step descriptions
with counts, and everything deliberately kept ("kept 3 legacy rrd:*
attr rows (additive-only)").

### Phase 3: Runtime slimming

`get_dbh` now calls `Munin::Master::Schema::verify($dbh)` (memoized per
process) -- the single choke point every consumer shares (update,
limits, html, graph, static renderers). `_db_init` is bootstrap-or-die:
fresh -> `create_schema` + `record`; unversioned -> the shared mismatch
message; versioned -> the same `verify` get_dbh runs. The state-columns,
`ds.deleted`, `ds_rrd` backfill/retire and notification-rename blocks
are gone from the runtime.

### Verification

- `make docker-test` (sqlite + fork, CI-equivalent): 37 files, 625
  tests, PASS -- the existing suite stayed green because every test
  database is fresh (bootstrap path) or opened through
  `TestUtils::dbh_rw` (bypasses `get_dbh`, unaffected by design).
- `make docker-test-matrix`: all three cells PASS (sqlite nofork,
  sqlite fork, pg). The pg cell exercises `ALTER TABLE ... ADD
  CONSTRAINT` (FK retrofit) and the `information_schema` introspection
  paths.
- `make docker-lint`: clean.
- New test file `t/munin_master_schema_migration.t`: ~110 assertions
  covering the spec's cases 1-10 (upgrade correctness vs fresh
  bootstrap, data preservation incl. the COALESCE '42' legacy mapping,
  audit trail, idempotency, fail-loud runtime and tool paths,
  --check/--dry-run exit codes and no-write guarantees, the full yolo
  ladder, extra-column classification in both modes, connection
  precedence, FK retrofit on both drivers).

---

## What We Learned

### Technical

- **`sort _split_cols($1)` does not sort.** Perl parses it as `sort
  SUBNAME LIST` -- `_split_cols` becomes the *comparator* (called with
  `$a, $b`), and the list comes back untouched. The fix is to assign
  first, then `sort @cols`. This one cost a pg-cell debugging round:
  composite PKs arrived in declaration order while the expected side was
  sorted, and every table with a composite PK looked "missing_pk".
- **`map { $_->{name} } @TABLES, 'version_history'`** -- the block
  applies to *all* following args, so `'version_history'->{name}` dies
  with "Can't use string as a HASH ref". Two occurrences (in `detect`
  and `known_tables`), both found by running the tool, not by reading.
- **PRAGMA row shapes bite:** `selectcol_arrayref("PRAGMA index_info(x)")`
  returns the *seqno* column (0,1,2...), not column names -- every
  unique set looked like `0|1` until the introspection used
  `selectall_arrayref` and mapped column 2.
- **sqlite rewrites `sqlite_master.sql` on `ALTER TABLE ADD COLUMN`**:
  the new column definition is inserted before the final `)`, so an
  upgraded table's stored DDL differs from a from-scratch render in
  punctuation placement (`0 , deleted` vs `0, deleted`). Normalized
  comparison must strip *all* whitespace; none of our DDL string
  literals contain spaces.
- **pg reformats CHECK expressions**: `CAST((x IS NOT NULL) AS INTEGER)`
  is stored as `((((x IS NOT NULL))::integer + ...))`. Exact-text
  comparison is impossible, so check matching on pg is
  identifier-coverage (every non-keyword token of the expected expr must
  appear in the stored one); sqlite keeps exact text.
- **pg makes PRIMARY KEY columns implicitly NOT NULL** and preserves
  composite-PK column order in `pg_get_constraintdef`; sqlite reports
  declared nullability and the pk ordinal. Both sides are normalized in
  `introspect`/`expected_schema` (sorted pk sets, pg-only notnull
  marking) so the fingerprint compares like with like.
- **Table rebuilds for FK retrofit need FKs OFF**: `DROP TABLE parent`
  with referencing rows fails under `PRAGMA foreign_keys=ON`, and the
  pragma is a no-op inside a transaction. The tool connects sqlite with
  `foreign_keys=OFF` and replaces the enforcement with a strict-mode
  post-migration integrity sweep (per-FK orphan counts, cross-driver,
  built from the same introspection data). Yolo keeps dangling rows and
  does not run the sweep -- additive-only means nothing is lost, only
  possibly inconsistent, exactly as the spec's risk table describes.
- **The dry-run recorder** (`$dbh->{private_munin_sql_log}`) means
  --dry-run executes the genuine migration path and rolls back, rather
  than printing a parallel hand-maintained SQL list. sqlite and pg both
  have transactional DDL, so the rollback is complete.
- **Circular `Update.pm` <-> `UpdateWorker.pm` require** compiles
  `Update.pm` twice; a fully-qualified constant without parens
  (`Munin::Master::Schema::CURRENT_SCHEMA_VERSION,`) is parsed as a
  bareword and fails the *inner* compile under `strict subs`. Parens
  fix it.
- **Test::More list-context trap:** `ok($x =~ /re/, "name")` expands to
  `ok("name")` when the match *fails* (a failed match with no captures
  is an empty list) -- the test false-passes with an empty name. Every
  `=~` inside `ok()` needs `scalar()` or an `&&` chain.

### Process

- The smoke-test loop (a standalone script hitting the tool as a
  subprocess before the TAP file existed) caught the introspection and
  narration bugs in minutes; writing the TAP file directly would have
  mixed fixture bugs with product bugs.
- Empirical probes beat speculation for driver behavior: the
  sqlite_master-rewrite fact, the pg CHECK normalization and the pg
  constraint catalog shapes were each probed in the dev container
  before the code was written. One probe script (`out/probe.pl`) settled
  the entire pg introspection design.
- The spec's "compare introspect() output against a fresh bootstrap"
  testing strategy is self-validating: it needs no golden expected
  values in the test file, and it fails the moment DDL and expectations
  drift apart.

---

## What We Decided

- **The notification -> notification_tracking rename moved into
  `migrate_v0_to_v1` as step 4.** The spec's four-step list predates the
  rename (added one commit before the spec was written) and its stated
  goal is "no migration logic remains in `_db_init`" -- leaving the
  rename in the runtime would violate that. It moves verbatim ("it
  moves, it does not get rewritten") and the golden v0 fixture carries
  `notification_tracking` directly, so the step is a no-op on fixtures
  and only fires for pre-rename databases.
- **`verify` lives in Schema.pm and both runtime paths use its message
  builder** (`mismatch_message`) so the `_db_init` and `get_dbh`
  failures are literally the same text, per the spec's "identical in
  shape" requirement.
- **The tool accepts `--config`/`--config_file`** (same spelling as
  `munin-update`): the connection-precedence contract is untestable
  without a way to name a config file, and "loaded exactly as
  munin-update loads it" implies the same flag.
- **Strict mode refuses on dangling references** (integrity sweep);
  yolo mode keeps and does not narrate them beyond the additive-only
  contract. The spec's yolo risk table explicitly tolerates "dangling
  references kept".
- **`specs/` is un-ignored in `.gitignore`** -- the spec's own open
  question resolves to "tracked: it is a contract, not a scratch note",
  and the ignore entry (filed under "Build artifacts") contradicted
  that.
- **Missing named indexes are created by yolo** (additive, narrated);
  missing CHECK constraints and UNIQUE sets are refused (sqlite cannot
  add them additively; adding a UNIQUE validates existing data).
- **Yolo audit rows**: one row per successful ladder run whose comment
  narrates everything applied, vs strict mode's one row per migration
  step. The spec's example fat comment is the yolo shape; "one row per
  applied step" is the strict shape.

---

## Rules Added

- **`scalar()` around `=~` in `ok()`:** any `ok($x =~ /re/, ...)`
  false-passes on match failure (list context). Use `ok(scalar($x =~
  /re/), ...)` or an `&&` chain.
- **Never `sort function(@args)`:** perl parses it as sort-with-
  comparator-sub. Assign to a variable first, then sort.
- **Driver probes before driver code:** before writing per-driver
  introspection, probe the actual catalog output (PRAGMA shapes,
  `information_schema`, `pg_get_constraintdef`) in the dev container.

---

## What We'd Do Differently

- The canonical schema structure earns its keep immediately, but the
  tool still reaches into Schema.pm privates (`_column_set`,
  `_table_spec`) for the yolo column-add loop. A small public
  `add_missing_columns($dbh)` (or rendering the ALTER from the same
  structure inside Schema.pm) would keep the layering clean.
- The pg CHECK identifier-coverage match is fuzzy by necessity. If pg
  support hardens, storing the expected check exprs in pg's own
  normalized form (rendered once against a scratch database) would make
  the comparison exact.
- The notification-rename step is the kind of thing the spec should
  have listed; when a spec enumerates migration steps, grep the
  runtime's DDL-touching code for migrations *after* the spec was
  drafted -- this one was added the day before.

---

## Files Changed

| File | Purpose |
|------|---------|
| `lib/Munin/Master/Schema.pm` | New: canonical DDL, `CURRENT_SCHEMA_VERSION`, `create_schema`, `record`, `detect`, `introspect`, `migrate_v0_to_v1`, `verify` + mismatch message, schema diff |
| `script/munin-upgrade-db` | New: offline migration CLI (`--check`, `--dry-run`, `--yolo`, connection precedence), postinst contract in POD |
| `t/lib/v0_schema.sql` | New: golden pre-versioning DDL (generated from the canonical specs minus ds_rrd/ds.deleted) |
| `t/munin_master_schema_migration.t` | New: fixture-based migration, idempotency, fail-loud, yolo-ladder, precedence tests; runs both matrix cells |
| `lib/Munin/Master/Update.pm` | `get_dbh` verifies (memoized); `_db_init` bootstrap-or-verify; migration blocks deleted |
| `Build.PL` | Register `script/munin-upgrade-db` |
| `.gitignore` | Un-ignore `specs/` (tracked contracts, not build artifacts) |
| `specs/README.md` | New: spec index |
| `specs/01_OFFLINE_SCHEMA_MIGRATION.md` | The spec itself (tracked now) |
| `doc/installation/upgrade.rst` | Postinst contract + fail-loud behavior for admins |

---

## Session 2: C-shaped perl for a C/Python audience (2026-10-03)

**Context:** Review point after the implementation landed: the audience
for this codebase is mostly C and Python developers, and perl gotchas
are dangerous for them. The ask: use only C patterns, avoid perl
idioms unless the idiom is obvious -- not "document the traps" but "do
not write the trap-prone code at all".

### What we did

- **Rewrote the session's perl in C shape.** `Schema.pm`,
  `script/munin-upgrade-db` and `t/munin_master_schema_migration.t`
  went from idiomatic perl (map/grep chains, postfix modifiers,
  `unless`, `//` ladders, closures for the dry-run callbacks) to
  explicit `for` loops over named variables, `if (...) { }` blocks, and
  an explicit precedence ladder in `_resolve_connection` that mirrors
  the CLI > env > config > default contract line by line. The dry-run /
  apply-step coderefs became a named `_run_migration_steps($dbh,
  $state, $target)` that both callers share. Behavior is unchanged --
  the test suite is the arbiter, and it stayed green throughout.
- **Fixed latent test bugs while building the guardrail.** The
  list-context probe found five pre-existing vacuous-pass assertions in
  `t/munin_master_limits.t` and `t/munin_master_spec.t`
  (`ok(grep { ... } @alarms, "name")`: a grep matching nothing returns
  an empty list, so ok() receives only the test name -- true -- and the
  test passes). All five became explicit loops with flags.
- **`make lint-perl-gotchas`**, wired into `make lint` as a hard
  dependency. Three evidence-based grep rules: (1) `sort NAME @list`
  with a builtin allowlist (builtins after `sort` are safe --
  prototypes and list-op parsing make them terms; user subs are the
  trap), (2) `ok()/is()/isnt()` containing `grep` or `=~`/`!~` without
  `scalar()`, (3) `map { ... }` followed by a comma-introducing-a-new
  list element. Each rule must point at a bug it would have caught; the
  mission log is the evidence register. Verified both directions: the
  clean tree passes, a synthetic probe file trips all three.
- **Docs:** HACKING.pod gained a "Perl pitfalls" section under Coding
  Style (the three traps, stated for C/Python readers); AGENTS.md
  gained the standing rule ("write C-shaped perl only...").

### What we learned

### Technical

- **`sort NAME @list` mis-parsing is narrower than feared, and the
  lint allowlist must reflect that.** Empirical probe: `sort readdir
  $dh`, `sort grep { } @list`, `sort keys %h`, `sort split /,/ $s`,
  `sort reverse @list` all sort correctly -- perl parses builtin
  list-operators and prototype-bearing functions as terms. Only
  *user-defined* subs become comparators. The first lint draft flagged
  the correct `sort readdir` code in `SpoolReader.pm`; the allowlist
  came from the probe, not from guesswork.
- **`|$` as a top-level grep -E alternative is a zero-width match that
  swallows every line.** The rule-1 exclusion meant to allow
  `sort keys` at end-of-line (`...[[:space:]()]|$$`) filtered out
  *everything*, and the lint silently passed a probe that should have
  failed. The `$` must sit inside the group: `(...)([[:space:]()]|$)`.
  A guardrail that cannot fail is worse than none -- probe both
  directions, always.
- **The `&&` exclusion for the ok()/is() rule is unsound.** `ok((grep
  { $a && $b } @list), "name")` -- the `&&` is *inside the grep block*,
  where it does nothing for the outer list context. One of the five
  real bugs found was exactly this shape and was being masked by the
  exclusion. Split the rule: no exclusions for grep-in-ok; `scalar(`
  only for match-in-ok.
- **C-shape improved the code, not just the safety.** The explicit
  precedence ladder in the tool now reads as the spec's contract; the
  named `_run_migration_steps` removed two closures; `problem_lines`
  and the dump builders became plain loops a C developer can diff.

### Process

- Rewrite-then-test (the suite stayed green across the whole
  conversion) beat annotate-and-hope: the traps could not re-emerge
  because the constructs are gone.
- The lint rules were derived from bugs that actually happened in this
  session, then verified to fire on synthetic violations and stay quiet
  on the real tree. Evidence-based lint has a chance of surviving;
  style-preference lint does not.

### Rules Added

- **C-shaped perl (promoted to AGENTS.md + HACKING.pod):** explicit
  for-loops, if-blocks; no map/grep chains, postfix modifiers,
  `unless`, `//` ladders, or `sort NAME @list`; `scalar()` any
  `=~`/grep inside `ok()`/`is()`.
- **`make lint-perl-gotchas`:** the three traps, grepped, wired into
  `make lint` as a hard dependency.

### What We'd Do Differently

- The first lint draft shipped with an unsound rule (the `&&`
  exclusion) and an over-broad one (flagging builtin `sort` forms)
  before the probe forced both corrections. Probe the guardrail against
  known-good *and* known-bad code in the same breath as writing it.
