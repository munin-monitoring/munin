# -*- makefile -*-

# This is the top level Makefile for Munin.

# Some actions are handled by Build.PL (see Module::Build). To only
# install the perl module, you can only

# Defaults/paths. Allows $(CONFIG) to be overrided by
# make command line
DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
include $(CONFIG)

PLUGINS		 := $(wildcard plugins/node.d.$(OSTYPE)/* plugins/node.d/* $(JAVA_PLUGINS))

.PHONY: default build install clean test testcover testpod testpodcoverage tar

default: build-munin

build-munin: Build

install: Build
	./Build install $(ifneq $(DESTDIR),,destdir=$(DESTDIR),

clean: Build
	./Build realclean
	rm -rf _stage
	rm -f MANIFEST META.json META.yml
	rm -f lib/Munin/Location.pm

##############################
# perl module

Build: Build.PL lib/Munin/Location.pm
	$(PERL) Build.PL destdir=$(DESTDIR) installdirs=$(INSTALLDIRS)

# Munin can always find and load its perl modules. We use this to
# point out where the configuration is installed.
lib/Munin.pm: lib/Munin.pm.in
	sed -e '/^# BEGIN_REPLACE/,/^# END_REPLACE/ c our $munin_conf = "$(CONFDIR)/munin.conf";\n\our $munin_node_conf = "$(CONFDIR)/munin-node.conf";' \
		$< > $@

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


##############################
# java plugin
include Makefile.javaplugin
