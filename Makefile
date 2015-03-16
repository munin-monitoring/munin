# -*- makefile -*-

# This Makefile provides convenience targets for common build/test/install cases, as well as rules
# for the release manager.

# In the interest of keeping this Makefile simple, it does not attempt to provide the flexibility
# provided by using Build.PL directly. (See perldoc Module::Build).

# Defaults/paths. Allows $(CONFIG) to be overrided by
# make command line
DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
include $(CONFIG)

.PHONY: default build install clean test testcover testpod testpodcoverage tar

default: blib

blib: Build
	./Build

install: Build
	./Build install --destdir=$(DESTDIR) --verbose


clean: Build
	./Build realclean
	rm -rf _stage
	rm -f MANIFEST META.json META.yml

##############################
# perl module

Build: Build.PL
	$(PERL) Build.PL --destdir=$(DESTDIR) --installdirs=$(INSTALLDIRS) --verbose

######################################################################
# testing

test: Build
	./Build test

testcover: Build
	./Build testcover

testpod: Build
	./Build testpod

testpodcoverage: Build
	./Build testpodcoverage

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
