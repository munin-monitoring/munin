.. _develop-tests:

=========================
 Munin development tests
=========================


Scope
=====

The tests we use check for different things.

* Is function x in module y working as expected?
* Can we establish an encrypted network connection between two
  components?
* Do we follow the perl style guidelines?
* Does this component scale well?

The code tests are broadly separated by scope.

Inspired by
https://pages.18f.gov/automated-testing-playbook/principles-practices-idioms/

Small
-----

In this category, we place tests for simple classes and functions,
preferably with fast execution and without using external resources.

Medium
------

Enabled with the TEST_MEDIUM variable set.

In this category, we test interaction between components.  These may
use the file system, fork processes, or access test data sets.

Large
-----

Enabled with the TEST_LARGE variable set.

In this category, we may test the entire system.

A munin master, node, and plugins all running together would be placed
in this category.

Performance and bottleneck testing would also be at home in this
category.


Running the tests
=================

The development container is the reference environment.  CI runs
exactly what you run locally, so tests are executed in docker by
default.  The image (``Dockerfile.dev``) ships every dependency the
suite needs, including a postgresql server (see
`The test matrix: FORK x DBDRIVER`_ below).

Build the image once after cloning (and rebuild whenever
``Dockerfile.dev`` changes; CI caches it keyed on that file's hash)::

   docker build -t munin-dev -f Dockerfile.dev .

Run the full suite::

   make docker-test

This configures and builds (``perl Build.PL && ./Build``), then runs
``prove --shuffle --timer -j$(nproc)`` over ``t/*.t`` inside the
container.  A green run is roughly 4 minutes on a modern laptop.
``--shuffle`` randomises test order on purpose: it mixes slow and fast
tests across jobs and doubles as an order-independence check.  The
harness log records the order used -- reproduce a run by passing those
files to prove in that order.

Useful targets::

   make docker-test-one FILE=munin_master_limits.t   # one test file
   make docker-show-fail                             # suite + failure summary
   make docker-lint                                  # perlcritic/shellcheck/codespell
   make docker-cover                                 # suite under Devel::Cover
   make docker-shell                                 # shell in the dev container
   make docker-test-matrix                           # sweep the CI test matrix

``prove`` knobs worth knowing (run inside the container or via
``docker-shell``): ``-v`` verbose TAP, ``--timer`` per-file durations,
``-j N`` parallel jobs, ``--state=slow|failed`` persistent scheduling
state in ``.prove``, ``--rules`` seq/par patterns, ``-D`` dry run.

.. warning::

   A passing local run outside docker is NOT proof that CI will pass:
   the container defines the dependency set, the perl version and the
   database backends.  Always run ``make docker-test`` before commit.
   Targeted subsets miss regressions -- a fixture change once passed
   a 4-test subset and failed ``spec.t`` only in the full run.


The test matrix: FORK x DBDRIVER
================================

Munin deployments differ in two dimensions that the suite must not
assume away:

* **Forking** -- production masters run ``fork 1``: update workers and
  the limits evaluation run under ``Parallel::ForkManager``.  Tests
  that pin ``fork 0`` never exercise those paths.
* **Database backend** -- the SQL layer supports sqlite and
  PostgreSQL.  SQL that is fine on sqlite can be invalid on pg (and
  vice versa); only running against both catches it.

``make docker-test`` takes two orthogonal arguments, one per
dimension::

   make docker-test FORK=0 DBDRIVER=sqlite   # serial + sqlite
   make docker-test FORK=1 DBDRIVER=sqlite   # parallel + sqlite
   make docker-test FORK=1 DBDRIVER=pg       # parallel + pgsql
   make docker-test FORK=0 DBDRIVER=pg       # runnable, but see below

Every combination is runnable.  CI selects the three that map to real
deployment shapes; ``FORK=0 DBDRIVER=pg`` is not *invalid*, it is just
not worth CPU cycles -- no deployment runs a serial master against
PostgreSQL.  If you need it locally, the argument works like any
other.  ``make docker-test-matrix`` sweeps the three CI configurations
sequentially.

The defaults are the usual local shape: ``FORK=1``, ``DBDRIVER=sqlite``,
``JOBS=$(nproc)``.  CI pins every configuration explicitly.  The arguments are
exported into the container as ``MUNIN_TEST_FORK`` and
``MUNIN_TEST_DBDRIVER``; test helpers read them (see
``TestUtils::fork_mode`` / ``db_driver``).  When you run ``prove``
by hand outside docker the env is absent and helpers default to the
usual shape.

What each dimension exercises:

* ``FORK=1`` -- the ``Parallel::ForkManager`` paths in
  ``Munin::Master::Update::_run_workers`` and
  ``Munin::Master::Limits::_evaluate_limits``: children opening their
  own handles, writing state concurrently, and being reaped.  Fork
  pins in tests go through ``TestUtils::fork_mode()`` instead of
  hard-coded ``0``.
* ``DBDRIVER=pg`` -- the PostgreSQL branches of
  ``Munin::Master::Update::_db_init`` (``SERIAL`` columns, the state
  and ledger migrations, the grp root row), ``get_dbh``'s Pg connect,
  and every ``ON CONFLICT`` upsert against a real server.  Test
  fixtures are generated into per-process scratch databases by
  ``t/lib/TestPG.pm`` (the dev image ships the server; outside the
  image those configurations skip cleanly).

``t/munin_master_limits_matrix.t`` is the focused version of the same
idea: one assertion body (state written, ledger stable and keyed by
service, notifications delivered, no leaked children, FK constraints
enforced) run against three configurations.  Without the matrix env it sweeps
all three; inside a CI matrix job it runs only the pinned configuration.


Test infrastructure (t/lib)
===========================

TestState
---------

Per-test state directories under tmpfs (``/dev/shm/munin-var-lib`` by
default; override with ``MUNIN_TEST_STATE_ROOT``).  Layout is
deterministic and greppable::

   <root>/<pid>-<testname>-<n>/

``TestState::state_dir()`` hands out a fresh directory per call.
Cleanup happens at process exit -- and is **pid-guarded**: forked
custom workers (PFM children) inherit the creation list and would
otherwise delete the master's directories when they exit.  ``kill -9``
leaks visibly, never silently.

TestUtils
---------

Shared plumbing; use it instead of copy-pasting setup blocks:

* ``setup_test_config()`` -- parse ``t/config/munin.conf``, allocate a
  TestState dbdir; returns ``($config, $dbdir)`` so callers add their
  own extra keys.
* ``generate_sample_db($dir)`` / ``generate_sample_db_and_rrds($dir)``
  -- build the SampleDB fixture (plus RRD files for render tests).
  On pg configurations the fixture goes to a fresh per-process scratch
  database; the return value is whatever you pass to ``dbh_ro`` /
  ``dbh_rw``.
* ``dbh_ro($dbfile)`` / ``dbh_rw($dbfile)`` -- the only sanctioned way
  for tests to open database handles.  Redundant ``AutoCommit`` and
  moot ``PrintError`` are deliberately omitted; do not re-add.
* ``generate_test_conf($dir, \@ports)`` -- integration-test munin.conf
  with the ephemeral ports forked test nodes actually bound.  Fork
  value follows the matrix configuration.
* ``mock_update_get_param($config)`` -- returns the
  ``Test::MockModule``; the caller must hold it or the mock dies.
* ``rglob($dir, $re)`` -- recursive glob via File::Find.  Core perl's
  ``glob('**/*.x')`` does NOT recurse; ``**`` silently degrades to
  ``*``.
* ``fork_mode()`` / ``db_driver()`` -- the matrix configuration, read from
  ``MUNIN_TEST_FORK`` / ``MUNIN_TEST_DBDRIVER``.

What is deliberately NOT factored: ``Logger::configure`` calls (args
vary and tests depend on the level), ``parse_config_from_file`` for
generated confs, and DBI connect boilerplate that carries real
variance.  Unifying those trades visible variance for hidden
parameters.  Factor by repeated *body*, not by repeated name.

TestPG
------

PostgreSQL support for pg configurations.  Starts the in-image cluster if
needed, waits for readiness, hands out ``munin_test_<pid>_<n>``
scratch databases (pid-suffixed: parallel prove jobs cannot collide),
drops them at process exit (pid-guarded, like TestState).  Every entry
point returns undef when no server is usable and the caller skips the
pg configurations -- that is the whole skip policy.

SampleDB / SampleRRD
---------------------

The synthetic fixture (5 hosts x 5 services x 15 DS, seeded alarms,
contacts, thresholds).  SampleDB builds its schema through the real
``Munin::Master::Update::_db_init`` -- never a private copy; a copied
schema drifts, hides production bugs and invites tests to encode the
drift as expectation.  It is driver-aware (``$dbfile, $driver``: a
filename for sqlite, a database name for pg) and produces identical
row counts on both engines.  Group names are the *leaf* of the path
chain, like production's config import names them (a group path
``acme.com/localhost`` is the group ``localhost`` under ``acme.com``,
per the ``[group;subgroup;host]`` config syntax).


Writing tests: rules the suite taught us
========================================

These are not style preferences; each one exists because ignoring it
broke something in CI:

* **No database handle may be open across a fork.**  Children inherit
  handles, and their exit-time ``DESTROY`` disconnects or rolls back
  *shared* state -- on pg the server tears down the connection and the
  master's next query dies with "server closed the connection
  unexpectedly".  The production phases follow the same rule: open,
  work, close, around every fork.
* **END-based cleanup in helpers must be pid-guarded.**  Forked
  children run END blocks too and will clean up the master's
  resources (state directories, scratch databases).
* **Pipe test doubles must consume stdin** to EOF like a real mailer.
  ``/bin/true`` exits at once -> EPIPE on every write -> refork storm
  -> zombie pileup.  ``perl -ne1`` reads to EOF, exits 0, prints
  nothing.
* **fork without waitpid is a bug.**  Reap children and surface their
  exit status; a child that died silently is indistinguishable from
  one that succeeded.
* **Fixture commands must be metacharacter-free** unless shell
  semantics are intended: single-string ``exec($cmd)`` re-runs through
  the shell when it sees any metacharacter.
* **Connection-behaviour PRAGMAs run before the transaction
  starts.**  sqlite silently ignores ``PRAGMA foreign_keys`` inside a
  transaction; ``get_dbh`` sets its PRAGMAs while autocommit is still
  on, then flips it.
* **Explain every deviation in a comment.**  When code does not use
  the shared helper for a step, say why at the site.  An unexplained
  deviation reads as an oversight and invites a well-meaning cleanup
  that breaks it (a test's faithful ``AutoCommit => 0`` mock once
  looked exactly like the cruft being removed).
* **Assert from first principles, not from the code under test.**
  Derive expectations from the fixture data and the documented
  contract.  Copying the implementation into the assertion proves
  only that the code agrees with itself.
* **Targeted runs miss regressions.**  The CI-equivalent full
  ``make docker-test`` before commit is non-negotiable.
* **Prove warning provenance by stash-compare.**  "I did not touch
  that file" is a hypothesis; re-run the same tests at the parent
  commit with your changes stashed and compare.
* **Spot-check diffs after bulk edits**, and grep for now-unused
  imports after moving code into a helper -- dead imports ship
  silently.
* **Verify tool defaults empirically** (a 6-line probe beats a
  memory-based claim), and probe before trusting filter semantics.


SQL portability (sqlite and PostgreSQL)
=======================================

The SQL layer runs on both backends; the suite runs on both, and the
rules below are what keeps the pg configurations green:

* ``x IS NOT NULL`` is 0/1 arithmetic on sqlite but yields booleans on
  pg, and pg has no ``+`` on booleans.  Write
  ``CAST((x IS NOT NULL) AS INTEGER) + ...`` -- accepted by both.
* pg has no ``ALTER TABLE ... ADD COLUMN IF EXISTS`` (that is MariaDB
  syntax).  Check ``information_schema.columns`` (pg) or
  ``PRAGMA table_info`` (sqlite) and ALTER only when missing.
* Upserts: ``INSERT ... ON CONFLICT (...) DO UPDATE`` works on both
  (sqlite 3.24+).  ``INSERT OR IGNORE`` is sqlite-only; prefer
  ``ON CONFLICT DO NOTHING``.
* Detect the driver from the handle you were given
  (``$dbh->{Driver}->{Name}``), not from ambient environment.  Env
  variables decide how ``get_dbh`` *connects*; code operating on a
  given handle must ask that handle.
* FK enforcement is off by default on sqlite.  ``get_dbh`` turns it on
  (outside a transaction) because the url/state FK columns are purely
  decorative otherwise.  Test fixtures enable it too -- fixture rows
  must satisfy the same constraints production enforces.
* A ``NULL`` in a unique-index column never collides: send-ledger
  upserts must carry the full key (``contact_id, service_id``) or
  rows grow unbounded and throttling never accumulates.


Coverage
========

``make docker-cover`` runs the suite under ``Devel::Cover`` and
generates ``cover_db/coverage.html`` plus a terminal summary.
Expect roughly **5x** the plain suite cost -- it is the long pole in
CI, and worth knowing when you touch hot paths.

Devel::Cover mechanics worth knowing:

* Each test process writes its own ``cover_db/runs/<timestamp>.<pid>``
  file; ``cover`` merges every run in that directory at report time.
  This is why ``prove -j`` needs no per-file databases, locking or
  merge choreography -- and why coverage from several jobs can be
  combined by simply gathering their run files into one directory.
* **The report must select loaded paths, not installed ones.**  Tests
  load production code from ``lib/`` via ``use lib``, so the coverage
  database contains ``lib/Munin/...`` paths and never
  ``blib/lib/...``.  CI's uploads were empty for a long time while
  paying the full instrumentation tax because the select matched
  ``blib/``.  The correct filter is report-time::

     cover -silent -select_re "^lib/Munin|^script/munin" -report html_basic

* In Devel::Cover 1.38, report-time ``-select`` does **not** filter
  and runtime ``-select`` does **not** prune collection; only
  ``-select_re`` (regex) filters, with a fall-back-to-all quirk when
  nothing matches.  Verify with ``cover -summary`` after a run.

In CI, coverage is a product of the test matrix: each configuration collects
into its own ``cover_db`` -- runs, structure AND digests.  The structure
is written by the collection phase into the base db; a runs-only archive
merges into a database the report cannot attribute (empty report, 0%
uploaded, green pipeline).  ``docker-cover`` tarballs the whole
``cover_db`` immediately after prove (``cover -report`` CONSUMES
``cover_db/runs``), and CI skips per-configuration reports
(``COVER_REPORT=0``).  A final job untars every configuration's database
and lets ``cover`` merge them itself --
``cover -report ... primary.db extra1.db extra2.db`` merges each
database's runs AND structure -- then reports once over the merged set
and uploads to
Coveralls **once** per workflow run.  Uploading from every configuration would
race: Coveralls treats each upload as the commit's status and the
last POST wins, so three parallel uploads would flap the published
number between single-configuration values.  The merged report is the union --
a branch covered in any configuration counts as covered.


Continuous integration
======================

``.github/workflows/build-n-test.yml`` runs on pushes and pull
requests to master:

* **lint** -- ``make docker-lint``: perlcritic (``.perlcriticrc``)
  over ``lib/`` and ``script/``, shellcheck, codespell, trailing
  whitespace.  Fatal, and a serial gate: the test matrix waits for it
  -- a lint failure must not spend three covered matrix jobs
  (~20 minutes each) discovering what lint already knew.
* **test matrix** -- three jobs, one per selected configuration
  (``JOBS=4 FORK=0 DBDRIVER=sqlite``, ``JOBS=4 FORK=1
  DBDRIVER=sqlite``, ``JOBS=4 FORK=1 DBDRIVER=pg``), each running
  ``make docker-test`` with those arguments.
* **coverage report** -- merges the run files collected by the matrix
  jobs, generates the HTML + summary, uploads to Coveralls once.

The dev image is cached with ``actions/cache`` keyed on the
``Dockerfile.dev`` hash -- after changing that file, expect one slow CI
run while the cache repopulates.


Mission logs: design history
============================

``mission_log/`` holds narrative records of significant work sessions:
what was tried, what failed and why, decisions and their rationale.
They are written for future maintainers -- the goal is to let yourself
forget, then find the reasoning again.  One log per workstream, with
``Session N`` continuations appended as work proceeds.  Conventions:
commit the work first, then document; the README stays generic (the
directory listing is the index); use ASCII (``--`` for dashes,
``->`` for arrows).  When you finish a substantial session, append to
the log -- the dead ends are as valuable as the wins.
