
# This Makefile provides convenience targets for common build/test/install cases, as well as rules
# for the release manager.

# In the interest of keeping this Makefile simple, it does not attempt to provide the flexibility
# provided by using Build.PL directly. (See perldoc Module::Build).

# Defaults/paths. Allows $(CONFIG) to be overridden by
# make command line
DEFAULTS = Makefile.config
CONFIG = Makefile.config

PYTHON_LINT_CALL ?= python3 -m flake8

include $(DEFAULTS)
ifneq ($(DEFAULTS),$(CONFIG))
    include $(CONFIG)
endif

# the perl script is used for most perl related activities
BUILD_SCRIPT = ./Build


.PHONY: default
default: build

.PHONY: help
help:
	@echo "Build targets:"
	@echo "    build"
	@echo "    clean"
	@echo "    doc"
	@echo "    install"
	@echo "    tar"
	@echo
	@echo "Test targets:"
	@echo "    lint"
	@echo "    test"
	@echo "    testcover"
	@echo "    testpod"
	@echo "    testpodcoverage"
	@echo

.PHONY: build
build: $(BUILD_SCRIPT)
	$(BUILD_SCRIPT)

.PHONY: doc
doc:
	$(MAKE) -C doc html

.PHONY: install
install: $(BUILD_SCRIPT)
	@# various directory placeholders (e.g. "@@SPOOLDIR@@") need to be replaced
	grep -Irl --null "@@" blib | xargs -0 sed -i \
		-e "$$(perl -I lib -M"Munin::Common::Defaults" \
		   -e "Munin::Common::Defaults->print_as_sed_substitutions();")"
	"$(BUILD_SCRIPT)" install --destdir="$(DESTDIR)" --verbose


.PHONY: apply-formatting
apply-formatting:
	# Format munin perl files with the recommend perltidy settings
	# This is recommend, but NOT mandatory
	@# select all scipts except munin-check
	perltidy script/munin-async script/munin-asyncd script/munin-cron.PL script/munin-doc script/munin-httpd script/munin-limits script/munin-node script/munin-node-configure script/munin-run script/munin-update
	@# format munin libraries
	find lib/ -type f -exec perltidy {} \;

.PHONY: lint lint-munin lint-perl-gotchas lint-plugins lint-spelling lint-whitespace

lint: lint-munin
	$(MAKE) lint-perl-gotchas
	$(MAKE) lint-plugins || true
	$(MAKE) lint-spelling || true
	$(MAKE) lint-whitespace || true

lint-munin: build
	# Scanning munin code
	perlcritic --profile .perlcriticrc lib/ script/
	shellcheck --shell dash getversion script/munin-get script/munin-cron

# Perl constructs that read as one thing and mean another. This codebase
# is maintained largely by C and Python developers; each rule here
# exists because the construct broke real code in this repository --
# see HACKING.pod ("Perl pitfalls") and
# mission_log/2026-10-03_offline_schema_migration.md. Keep the list
# evidence-based: every rule must point at a bug it would have caught.
# (Writing in C-shaped perl -- explicit loops, if-blocks -- avoids all
# of these by construction; the lint is the net for what slips past.)
lint-perl-gotchas: PERL_GOTCHA_FILES = $(shell find lib script t xt -type f \( -name '*.pm' -o -name '*.pl' -o -name '*.t' -o -name '*.PL' \) 2>/dev/null)
lint-perl-gotchas:
	@# 1. sort NAME @list parses as sort-with-comparator-subroutine: the
	@#    list comes back UNSORTED. Builtins (keys/map/grep/readdir/...) are
	@#    exempt -- prototypes and list-op parsing make them terms. Write
	@#    sort \&name, a sort { } block, or assign-then-sort.
	@# 2. ok()/is()/isnt() evaluate their arguments in LIST context: a grep
	@#    or match that comes back empty leaves only the test name, and the
	@#    test passes vacuously. Wrap the condition in scalar() or use an
	@#    explicit loop with a flag.
	@# 3. map { ... } @a, 'literal' -- the block applies to EVERY following
	@#    list argument, not just @a. Assign the list to a variable first.
	@bad1=$$(grep -rnE 'sort[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' $(PERL_GOTCHA_FILES) \
		| grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
		| grep -vE 'sort[[:space:]]+(\{|&|\$$|@|%|")' \
		| grep -vE 'sort[[:space:]]+(keys|values|map|grep|sort|qw|readdir|split|reverse|uc|lc)([[:space:]()]|$$)'); \
	bad2=$$(grep -rnE '\b(ok|is|isnt)[[:space:]]*\((\()?grep|\b(ok|is|isnt)[[:space:]]*\(.*(~=|=~|!~)' $(PERL_GOTCHA_FILES) \
		| grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
		| grep -vE 'scalar\('); \
	bad3=$$(grep -rnE '(^|[^%A-Za-z0-9_])map[[:space:]]*\{.*\}[[:space:]]+[^();,]*,[[:space:]]*(["'"'"'@])' $(PERL_GOTCHA_FILES) \
		| grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'); \
	if [ -n "$$bad1" ] || [ -n "$$bad2" ] || [ -n "$$bad3" ]; then \
		echo 'Perl gotchas (see HACKING.pod, "Perl pitfalls"):'; \
		if [ -n "$$bad1" ]; then \
			echo '  sort-with-comparator-sub (assign first, then sort, or use sort \&name / sort { }):'; \
			echo "$$bad1" | sed 's/^/    /'; \
		fi; \
		if [ -n "$$bad2" ]; then \
			echo '  match/grep in list context inside ok()/is() (wrap in scalar() or use an explicit loop):'; \
			echo "$$bad2" | sed 's/^/    /'; \
		fi; \
		if [ -n "$$bad3" ]; then \
			echo '  map block over a comma-list (assign the list first):'; \
			echo "$$bad3" | sed 's/^/    /'; \
		fi; \
		false; fi 2>&1

lint-plugins:
	@# SC1008: ignore our weird shebang (substituted later)
	@# SC1090: ignore sourcing of files with variable in path
	@# SC2009: do not complain about "ps ... | grep" calls (may be platform specific)
	@# SC2126: tolerate "grep | wc -l" (simple and widespread) instead of "grep -c"
	# TODO: fix the remaining shellcheck issues for the missing platforms:
	#       aix, darwin, netbsd, sunos
	#       (these require tests with their specific shell implementations)
	find plugins/node.d/ \
			plugins/node.d.cygwin/ \
			plugins/node.d.debug/ \
			plugins/node.d.linux/ -type f -print0 \
		| xargs -0 grep -l --null '^#!.*/bin/sh' \
			| xargs -0 shellcheck --exclude=SC1008,SC1090,SC2009,SC2126 --shell dash
	find plugins/ -type f -print0 \
		| xargs -0 grep -l --null "^#!.*/bin/bash" \
			| xargs -0 shellcheck --exclude=SC1008,SC1090,SC2009,SC2126 --shell bash
	find plugins/ -type f -print0 \
		| xargs -0 grep -l --null "^#!.*python" \
			| xargs -0 $(PYTHON_LINT_CALL)
	# TODO: perl plugins currently fail with perlcritic
	# verify that no multigraph plugin lacks a check for the node's capability
	# Three capability checks are detected:
	#     * perl: need__multigraph();
	#     * shell: is_multigraph
	#     * perl with "Munin::Plugin::Framework": we assume the framework takes care for it
	#     * manual: evaluate environment variable MUNIN_CAP_MULTIGRAPH
	# Some files are excluded from the test:
	#     * plugins/node.d.debug/*: these plugins are used only for testing
	#     * AbstractMultiGraphsProvider.java: this is not a plugin
	plugins_without_multigraph_check=$$(grep -rlwZ "multigraph" plugins/ \
		| xargs -r -0 grep -LwE '((need|is)_multigraph|Munin::Plugin::Framework|MUNIN_CAP_MULTIGRAPH)' \
		| grep -vE 'plugins/(node\.d\.debug/|.*/AbstractMultiGraphsProvider\.java)'); \
		if [ -n "$$plugins_without_multigraph_check" ]; then \
			echo '[ERROR] Some plugins lack a "multigraph" check (e.g. "needs_multigraph();" or "is_multigraph"):'; \
			echo "$$plugins_without_multigraph_check" | sed 's/^/\t/'; false; fi >&2

lint-spelling: CODESPELL_ARGS += --exclude-file=.codespell.exclude
# codespell introduced "--ignore-words" in v1.14 (Debian Buster)
lint-spelling: CODESPELL_ARGS += $(shell if codespell --help | grep -q " --ignore-words "; then echo "--ignore-words=.codespell.ignore-words"; fi)
lint-spelling:
	# codespell misdetections may be ignored by adding the full line of text to the file .codespell.exclude
	find . -type f -print0 \
		| grep --null-data -vE '^\./(\.git|\.pc|doc/_build|blib|.*/blib|build|sandbox|web/static/js|contrib/plugin-gallery/www/static/js)/' \
		| grep --null-data -vE '\.(svg|png|gif|ico|css|woff|woff2|ttf|eot|pem)$$' \
		| xargs -0 -r codespell $(CODESPELL_ARGS)

lint-whitespace: FILES_WITH_TRAILING_WHITESPACE = $(shell grep -r -l --binary-files=without-match \
				--exclude-dir=.git --exclude-dir=sandbox '\s$$' . \
			| grep -vE '/(blib|build|_build|web/static)/' \
			| grep -vE '/logo\.eps$$')

lint-whitespace:
	@if [ -n "$(FILES_WITH_TRAILING_WHITESPACE)" ]; then \
		echo 'Files containing trailing whitespace or non-native line endings:'; \
		printf '\t%s\n' $(FILES_WITH_TRAILING_WHITESPACE); \
		false; fi 2>&1


.PHONY: clean
clean: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" realclean
	rm -rf _stage
	rm -f MANIFEST META.json META.yml
	$(MAKE) -C doc clean


##############################
# perl module

$(BUILD_SCRIPT): Build.PL
	$(PERL) Build.PL --destdir="$(DESTDIR)" --installdirs="$(INSTALLDIRS)" --verbose


######################################################################
# testing

TEST_FILES_ARG = $(addprefix --test_files , $(TEST_FILES))

.PHONY: test
test: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" test $(TEST_FILES_ARG)

.PHONY: testcover
testcover: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testcover $(TEST_FILES_ARG)

.PHONY: testpod
testpod: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testpod $(TEST_FILES_ARG)

.PHONY: testpodcoverage
testpodcoverage: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testpodcoverage $(TEST_FILES_ARG)


######################################################################
# Rules for the release manager

RELEASE := $(shell $(CURDIR)/getversion)

.PHONY: tar
tar: munin-$(RELEASE).tar.gz.sha256sum

.PHONY: tar-signed
tar-signed: munin-$(RELEASE).tar.gz.asc

munin-$(RELEASE).tar.gz:
	@# prevent the RELEASE file from misleading the "getversion" script
	rm -f RELEASE
	tempdir=$$(mktemp -d) \
		&& mkdir -p "$$tempdir/munin-$(RELEASE)/" \
		&& echo $(RELEASE) > "$$tempdir/munin-$(RELEASE)/RELEASE" \
		&& git archive --prefix=munin-$(RELEASE)/ --format=tar --output "$$tempdir/export.tar" HEAD \
		&& tar --append --file "$$tempdir/export.tar" --owner=root --group=root -C "$$tempdir" "munin-$(RELEASE)/RELEASE" \
		&& gzip -9 <"$$tempdir/export.tar" >"munin-$(RELEASE).tar.gz" \
		&& rm -rf "$$tempdir"

munin-$(RELEASE).tar.gz.sha256sum: munin-$(RELEASE).tar.gz
	sha256sum "$<" >"$@"

munin-$(RELEASE).tar.gz.asc: munin-$(RELEASE).tar.gz
	gpg --armor --detach-sign --sign "$<"

.PHONY: tar-upload
tar-upload: tar tar-signed
	@if [ -z "$(UPLOAD_DIR)" ]; then echo "You need to set UPLOAD_DIR (e.g. '/srv/www/downloads.munin-monitoring.org/munin/stable')" >&2; false; fi
	@if [ -z "$(UPLOAD_HOST)" ]; then echo "You need to set UPLOAD_HOST" >&2; false; fi
	{ \
		echo "mkdir $(UPLOAD_DIR)/$(VERSION)"; \
		echo "put munin-$(VERSION).tar.gz* $(UPLOAD_DIR)/$(VERSION)/"; \
	} | sftp -b - "$(UPLOAD_HOST)"

.PHONY: docker

# Run with `DOCKER=podman` to build with podman instead of docker.
DOCKER ?= docker

docker-base:
	$(DOCKER) build -t munin:base -f Dockerfile.base .
docker: docker-base
	./getversion > RELEASE.docker
	$(DOCKER) build -t munin:latest .
	$(DOCKER) rm -f munin || true
	# Add the following to enable strace in the container
	# --security-opt seccomp:unconfined
	$(DOCKER) run --name munin --shm-size=256M -p 4948:4948 -itd munin:latest dev_scripts/noop

docker-connect:
	$(DOCKER) exec -it munin bash

docker-dev:
	$(DOCKER) compose up --build

docker-dev-stop:
	$(DOCKER) compose down

# --- Test execution -------------------------------------------------------
# prove --shuffle mixes slow and fast tests across jobs; a hand-maintained
# order is fragile as the suite changes. The harness log records the order
# used -- reproduce locally by passing those files to prove in that order.
JOBS  ?= $(shell nproc)
TESTS ?= t/*.t
PROVE  = prove --shuffle --timer -j$(JOBS) -Iblib/lib -Iblib/arch

# Test-matrix configuration selection. Every FORK x DBDRIVER combination is
# runnable (e.g. FORK=0 DBDRIVER=pg works locally); the CI matrix
# simply selects the three that map to real deployment shapes --
# serial+pgsql is not invalid, just not worth CPU cycles. Default =
# the usual local shape: sqlite + fork + jobs=nproc. CI pins every
# configuration explicitly. docker-test-matrix sweeps the CI configurations locally.
FORK     ?= 1
DBDRIVER ?= sqlite
TESTENV   = -e MUNIN_TEST_FORK=$(FORK) -e MUNIN_TEST_DBDRIVER=$(DBDRIVER)

# Run tests in Docker - same env as CI
docker-test:
	$(DOCKER) run --rm --shm-size=512m $(TESTENV) --add-host testing.acme.com:127.0.0.1 \
		-v $(CURDIR):/app munin-dev sh -c 'TMPDIR=/dev/shm perl Build.PL && TMPDIR=/dev/shm ./Build && TMPDIR=/dev/shm $(PROVE) $(TESTS)'

docker-test-one:
	$(DOCKER) run --rm --shm-size=256m $(TESTENV) --add-host testing.acme.com:127.0.0.1 \
		-v $(CURDIR):/app munin-dev sh -c 'TMPDIR=/dev/shm perl Build.PL && TMPDIR=/dev/shm ./Build && TMPDIR=/dev/shm prove --timer -j1 -Iblib/lib -Iblib/arch t/$(FILE)'

# Run tests and show failure summary at end
docker-show-fail:
	$(DOCKER) run --rm --shm-size=512m $(TESTENV) --add-host testing.acme.com:127.0.0.1 \
		-v $(CURDIR):/app munin-dev sh -c 'TMPDIR=/dev/shm perl Build.PL && TMPDIR=/dev/shm ./Build && TMPDIR=/dev/shm $(PROVE) $(TESTS) > /tmp/test-output.log 2>&1; RC=$$?; cat /tmp/test-output.log; if [ $$RC -ne 0 ]; then ./script/show-test-failures /tmp/test-output.log; fi; exit $$RC'

# Run lint in Docker
docker-lint:
	$(DOCKER) run --rm -v $(CURDIR):/app munin-dev sh -c 'perl Build.PL && make lint'

# Sweep the CI test matrix locally -- the local dev version of the
# GitHub Actions test matrix: the same three configurations, the same
# FORK/DBDRIVER arguments, run sequentially (CI runs them as parallel
# jobs). Cost-consciousness is a local-dev concern only; CI always
# runs the full matrix. The fourth combination (FORK=0 DBDRIVER=pg) is
# runnable but unselected; invoke docker-test with those args directly
# if you need it.
.PHONY: docker-test-matrix
docker-test-matrix:
	$(MAKE) docker-test JOBS=$(JOBS) FORK=0 DBDRIVER=sqlite
	$(MAKE) docker-test JOBS=$(JOBS) FORK=1 DBDRIVER=sqlite
	$(MAKE) docker-test JOBS=$(JOBS) FORK=1 DBDRIVER=pg

# Shell into dev container
docker-shell:
	$(DOCKER) run --rm -it --shm-size=128m -v $(CURDIR):/app munin-dev bash

# Run coverage in Docker: TWO prove passes under Devel::Cover -- the
# fixed shape for every configuration, no knobs (uniformity across
# matrix variants keeps cross-variant bug comparisons honest:
# mission_log/2026-10-04_covered_parallel_perf.md).
#
#   1. par pass: tests that do not exercise fork mode, -j$(JOBS)
#   2. seq pass: the fork-mode tests, one at a time (-j1), box-exclusive
#
# Why split: fork-mode tests fan out internally -- the master forks one
# worker per service per update cycle (25 with SampleDB), and
# Devel::Cover 1.38 charges EVERY forked child a full report() at exit
# (own runs/ dir + full structure rewrite + digests into the shared
# base db; ~4.4s per child measured). Under -j4 several fork tests
# overlap: parallel-of-parallel -- same cores, more contention, no
# extra throughput. The fork list is DERIVED from the tests (grep for
# fork_mode/MUNIN_TEST_FORK) so it cannot drift as tests change.
# Whole-suite shape: with a single-file TESTS the par pass may be
# empty -- use docker-test-one for single tests.
#
# Coverage collection: Debian's Devel::Cover 1.38 IGNORES
# $DEVEL_COVER_DB (probed: both passes collected into the default
# ./cover_db when the env was set -- run-dir timestamps span the whole
# run; the only DEVEL_COVER_* vars in the source are NO_COVERAGE and
# DB_FORMAT). So the two passes SHARE the default dir sequentially:
# par pass collects, its whole db (runs/ + structure/ + digests) is
# tarred, the dir is removed, seq pass collects fresh, tarred again.
# `cover -report` CONSUMES runs/ (merges into the db and clears it),
# so collect-then-tar before any report. CI uploads both tarballs per
# configuration (cover_db_par.tgz + cover_db_seq.tgz); the coverage
# merge job needs NO change -- its cover-db-* download pattern and the
# cover_db-*/ report glob are config-agnostic, so the union report
# simply merges more databases. -select_re filters to production code
# at report time: tests load modules from lib/ via "use lib", so the
# old "blib/lib|blib/script" select matched nothing (coverage uploaded
# to Coveralls was empty).
COVER_REPORT       ?= 1
COVER_DB_TARBALL   ?= cover_db.tgz
PROVE_J1           = prove --shuffle --timer -j1 -Iblib/lib -Iblib/arch
ALL_TESTS          := $(shell ls $(TESTS) 2>/dev/null)
FORK_TESTS         := $(shell grep -l 'TestUtils::fork_mode\|MUNIN_TEST_FORK' $(ALL_TESTS) 2>/dev/null)
PAR_TESTS          := $(filter-out $(FORK_TESTS),$(ALL_TESTS))
COVER_DB_TARBALL_PAR = $(COVER_DB_TARBALL:.tgz=_par.tgz)
COVER_DB_TARBALL_SEQ = $(COVER_DB_TARBALL:.tgz=_seq.tgz)
# COVER_REPORT=1 (local default): report over BOTH passes at the end
# -- the same multi-db merge shape the CI coverage job uses
# (`cover -report X primary extra...` merges runs AND structure). The
# par tarball is extracted beside the live seq db to feed the merge.
# COVER_REPORT=0 (CI) skips it; the merge job reports once.
COVER_REPORT_CMDS_1 = && mkdir -p cover_db_par && tar xzf $(COVER_DB_TARBALL_PAR) -C cover_db_par --strip-components=1 && cover -silent -select_re "^lib/Munin|^script/munin" -report html_basic -outputdir cover_report cover_db cover_db_par && cover -silent -select_re "^lib/Munin|^script/munin" -summary cover_db cover_db_par
COVER_REPORT_CMDS_0 =

docker-cover:
	$(DOCKER) run --rm --shm-size=1g $(TESTENV) --add-host testing.acme.com:127.0.0.1 \
		-v $(CURDIR):/app munin-dev sh -c 'TMPDIR=/dev/shm \
		perl Build.PL && \
		./Build && \
		rm -rf cover_db cover_db_par $(COVER_DB_TARBALL_PAR) $(COVER_DB_TARBALL_SEQ) && \
		PERL5OPT="-MDevel::Cover" TMPDIR=/dev/shm $(PROVE) $(PAR_TESTS) && \
		tar czf $(COVER_DB_TARBALL_PAR) cover_db && \
		echo "par pass runs: $$(ls cover_db/runs | wc -l)" && \
		rm -rf cover_db && \
		PERL5OPT="-MDevel::Cover" TMPDIR=/dev/shm $(PROVE_J1) $(FORK_TESTS) && \
		tar czf $(COVER_DB_TARBALL_SEQ) cover_db && \
		echo "seq pass runs: $$(ls cover_db/runs | wc -l)" $(COVER_REPORT_CMDS_$(COVER_REPORT))'

