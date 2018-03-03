
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

.PHONY: default build install clean test testcover testpod testpodcoverage tar

default: build

build: $(BUILD_SCRIPT)

install: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" install --destdir=$(DESTDIR) --verbose


clean: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" realclean
	rm -rf _stage
	rm -f MANIFEST META.json META.yml

##############################
# perl module

$(BUILD_SCRIPT): Build.PL
	$(PERL) Build.PL --destdir=$(DESTDIR) --installdirs=$(INSTALLDIRS) --verbose

######################################################################
# testing

test: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" test

testcover: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testcover

testpod: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testpod

testpodcoverage: $(BUILD_SCRIPT)
	"$(BUILD_SCRIPT)" testpodcoverage

######################################################################
# Rules for the release manager

RELEASE := $(shell $(CURDIR)/getversion)

tar:
	git archive --prefix=munin-$(RELEASE)/ --format=tar --output ../munin-$(RELEASE).tar HEAD
	mkdir -p munin-$(RELEASE)/
	echo $(RELEASE) > munin-$(RELEASE)/RELEASE
	tar rf ../munin-$(RELEASE).tar --owner=root --group=root munin-$(RELEASE)/RELEASE
	rm -rf munin-$(RELEASE)
	gzip -f -9 ../munin-$(RELEASE).tar
