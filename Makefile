
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

.PHONY: lint lint-munin lint-plugins lint-spelling lint-whitespace

lint: lint-munin lint-plugins lint-spelling lint-whitespace

lint-munin: build
	# Scanning munin code
	perlcritic --profile .perlcriticrc lib/ script/
	shellcheck --shell dash getversion script/munin-get script/munin-cron

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

docker-dev: docker-base
	$(DOCKER) build -t munin:dev -f Dockerfile.dev .
	$(DOCKER) run --rm --name munin-dev -v $(shell pwd):/munin -p 8000:8000 -p 14947:4947 -p 14948:4948 -it munin:dev
