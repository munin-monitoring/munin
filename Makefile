
# This Makefile provides convenience targets for common build/test/install cases, as well as rules
# for the release manager.

# In the interest of keeping this Makefile simple, it does not attempt to provide the flexibility
# provided by using Build.PL directly. (See perldoc Module::Build).

# Defaults/paths. Allows $(CONFIG) to be overridden by
# make command line
DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
include $(CONFIG)

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
	@echo "    test"
	@echo "    testcover"
	@echo "    testpod"
	@echo "    testpodcoverage"
	@echo

.PHONY: build
build: $(BUILD_SCRIPT)

.PHONY: doc
doc:
	$(MAKE) -C doc html

.PHONY: install
install: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" install --destdir=$(DESTDIR) --verbose

.PHONY: clean
clean: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" realclean
	rm -rf _stage
	rm -f MANIFEST META.json META.yml
	$(MAKE) -C doc clean


##############################
# perl module

$(BUILD_SCRIPT): Build.PL
	$(PERL) Build.PL --destdir=$(DESTDIR) --installdirs=$(INSTALLDIRS) --verbose


######################################################################
# testing

.PHONY: test
test: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" test

.PHONY: testcover
testcover: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testcover

.PHONY: testpod
testpod: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testpod

.PHONY: testpodcoverage
testpodcoverage: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testpodcoverage


######################################################################
# Rules for the release manager

RELEASE := $(shell $(CURDIR)/getversion)

.PHONY: tar
tar:
	git archive --prefix=munin-$(RELEASE)/ --format=tar --output ../munin-$(RELEASE).tar HEAD
	mkdir -p munin-$(RELEASE)/
	echo $(RELEASE) > munin-$(RELEASE)/RELEASE
	tar rf ../munin-$(RELEASE).tar --owner=root --group=root munin-$(RELEASE)/RELEASE
	rm -rf munin-$(RELEASE)
	gzip -f -9 ../munin-$(RELEASE).tar
