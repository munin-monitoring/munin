# -*- makefile -*-
#
# Gnu make only.  Seriously.
#
# $Id$

# Defaults/paths. Allows $(CONFIG) to be overridden by
# make command line
DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
ifneq ($(DEFAULTS),$(CONFIG))
    include $(CONFIG)
endif

ifeq ($(JCVALID),yes)
JAVA_BUILD=build-plugins-java
JAVA_INSTALL=install-plugins-java
JAVA_PLUGINS=plugins/node.d.java/*
endif

RELEASE          := $(shell $(CURDIR)/getversion)
INSTALL_PLUGINS ?= "auto manual contrib snmpauto"
INSTALL          := ./install-sh
DIR              := $(shell /bin/pwd | sed 's/^.*\///')
INFILES          := $(shell find . -name '*.in' | sed 's/\.\/\(.*\)\.in$$/build\/\1/')
INFILES_MASTER   := $(shell find master -name '*.in' | sed 's/\(.*\)\.in$$/build\/\1/')
CLASSFILES       := $(shell find plugins/javalib -name '*.java' | sed 's/\(.*\)\.java$$/build\/\1.class/')
PLUGINS          := $(wildcard plugins/node.d.$(OSTYPE)/* plugins/node.d/* $(JAVA_PLUGINS))
MANCENTER        := "Munin Documentation"
MAN8             := master/_bin/munin-update master/_bin/munin-limits master/_bin/munin-html master/_bin/munin-graph
PODMAN8          := build/master/doc/munin-cron master/doc/munin master/doc/munin-check
PODMAN5          := build/master/doc/munin.conf node/doc/munin-node.conf
PYTHON_LINT_CALL ?= python3 -m flake8
CONFVAR_SUBSTITUTION_FILES = \
	master/blib/libdoc/Munin\:\:Master\:\:HTMLOld.3pm \
	master/blib/lib/Munin/Master/HTMLOld.pm \
	node/blib/sbin/munin-node-configure \
	node/blib/sbin/munin-node \
	node/blib/sbin/munin-run \
	build/doc/munin-node.conf.5
MAKEFILES        := Makefile $(DEFAULTS) $(CONFIG)

# TODO: remove this fallback code for "make v3.x" (up to Debian Wheezy / Ubuntu Trusty) as soon as
#       the CI supports a more modern distribution
#       (see https://docs.travis-ci.com/user/reference/overview/)
# Make v3.x failed to handle colon escaping properly - thus we remove complicated filenames from
# targets and dependencies.  This may affect corner cases of dependency handling for the one file
# above containing a colon.  But in this case it is just about substituting paths in a
# documentation file - thus we can live with this rare risk of incorrectness.
ifeq ($(firstword $(subst ., ,$(MAKE_VERSION))),3)
# weed out all complicated filenames containing a colon
CONFVAR_SUBSTITUTION_DEP_FILES = $(shell printf '%s\n' $(CONFVAR_SUBSTITUTION_FILES) | grep -v ":")
else
CONFVAR_SUBSTITUTION_DEP_FILES = $(CONFVAR_SUBSTITUTION_FILES)
endif


.PHONY: install install-pre install-master-prime install-node-prime install-node-pre install-common-prime install-doc install-man \
	build build-common build-common-pre build-doc \
	substitute-build-defaults-inline substitute-confvar-inline \
	source_dist \
	test lint clean \
	clean-% test-% build-% install-% \
	tags \
	infiles

.SECONDARY: node/Build master/Build plugins/Build

.SUFFIXES: .java .class

# This HAS to be the 1st rule
default: build

.java.class:
	$(JC) -sourcepath plugins/javalib -d build/plugins/javalib $(JFLAGS) plugins/javalib/$(subst plugins/javalib/,,$*.java)

uninstall:
	echo "Uninstall is not implemented yet"

# This removes the installed config so that the next install-pass installs
# a new config.  Target _only_ suitable for maintainers.
unconfig:
	rm -f $(HTMLDIR)/.htaccess
	rm -f $(CONFDIR)/munin.conf

tags:
	-rm -f TAGS
	find master common -type f | egrep -v '/(build/|_build/|blib/|\.svn/)' | grep -v '\.t$$' | fgrep -v '~' | xargs etags -l perl -a

######################################################################

install: install-master-prime install-common-prime install-node-prime install-plugins-prime $(JAVA_INSTALL) install-man install-async-prime

install-pre: $(MAKEFILES)
	@$(CHECKUSER)
	mkdir -p $(LOGDIR)
	mkdir -p $(STATEDIR)
	mkdir -p $(SPOOLDIR)
	mkdir -p $(CONFDIR)
	$(CHOWN) $(USER) $(LOGDIR) $(STATEDIR) $(SPOOLDIR)

install-master-prime: $(INFILES_MASTER) install-pre install-master
	mkdir -p $(CONFDIR)/templates
	mkdir -p $(CONFDIR)/static
	mkdir -p $(CONFDIR)/templates/partial
	mkdir -p $(CONFDIR)/munin-conf.d
	mkdir -p $(LIBDIR)
	mkdir -p $(BINDIR)
	mkdir -p $(PERLLIB)
	mkdir -p $(PERLLIB)/Munin/Master
	mkdir -p $(HTMLDIR)
	mkdir -p $(DBDIR)
	mkdir -p $(DBDIR)/cgi-tmp
	mkdir -p $(CGIDIR)

	$(CHOWN) $(USER) $(HTMLDIR) $(DBDIR)
	$(CHMOD) 0755 $(DBDIR)

	$(CHOWN) $(CGIUSER) $(DBDIR)/cgi-tmp
	$(CHMOD) 0755 $(DBDIR)/cgi-tmp

	for p in master/www/*.tmpl ;  do \
		$(INSTALL) -m 0644 "$$p" $(CONFDIR)/templates/ ; \
	done

	for p in master/static/* ; do \
		$(INSTALL) -m 0644 "$$p" $(CONFDIR)/static/ ; \
	done

	for p in master/www/partial/*.tmpl; do \
		$(INSTALL) -m 0644 "$$p" $(CONFDIR)/templates/partial/ ; \
	done

	$(INSTALL) -m 0644 master/DejaVuSansMono.ttf $(LIBDIR)/
	$(INSTALL) -m 0644 master/DejaVuSans.ttf $(LIBDIR)/

	test -f $(HTMLDIR)/.htaccess || $(INSTALL) -m 0644 build/master/www/munin-htaccess $(HTMLDIR)/.htaccess
	test -f "$(CONFDIR)/munin.conf"  || $(INSTALL) -m 0644 build/master/munin.conf $(CONFDIR)/

	$(INSTALL) -m 0755 build/master/_bin/munin-cron $(BINDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-check $(BINDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-update $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-html $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-graph $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-limits $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-datafile2storable $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-storable2datafile $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-cgi-graph $(CGIDIR)/munin-cgi-graph
	$(INSTALL) -m 0755 build/master/_bin/munin-cgi-html $(CGIDIR)/munin-cgi-html

# Not ready to be installed yet
# $(INSTALL) -m 0755 build/master/_bin/munin-gather $(LIBDIR)/

install-node-plugins: install-plugins-prime

install-plugins-prime: install-plugins build $(PLUGINS) $(MAKEFILES)
	@$(CHECKGROUP)

	mkdir -p $(CONFDIR)/plugins
	mkdir -p $(CONFDIR)/plugin-conf.d
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(PLUGSTATE)

	$(CHOWN) root:root $(PLUGSTATE)
	$(CHMOD) 0755 $(PLUGSTATE)
	$(CHMOD) 0755 $(CONFDIR)/plugin-conf.d

	@# Process the OS specific plugins at the end. Otherwise they would be overridden by the
	@# generic ones.
	for p in build/plugins/node.d/* build/plugins/node.d.$(OSTYPE)/* ; do \
		if test -f "$$p"; then \
			echo Installing $$p; \
			$(INSTALL) -m 0755 $$p $(LIBDIR)/plugins/; \
		fi \
	done
	@# Some HP-UX plugins need *.adv support files in LIBDIR
	if [ "$(OSTYPE)" = "hp-ux" ]; then mv $(LIBDIR)/plugins/*.adv $(LIBDIR); fi
	$(INSTALL) -m 0644 build/plugins/plugins.history $(LIBDIR)/plugins/
	$(INSTALL) -m 0644 build/plugins/plugin.sh $(LIBDIR)/plugins/

install-plugins-java: build-plugins-java
	mkdir -p $(JAVALIBDIR)
	$(INSTALL) -m 0644 build/plugins/javalib/munin-jmx-plugins.jar $(JAVALIBDIR)/
	mkdir -p $(LIBDIR)/plugins
	for p in build/plugins/node.d.java/*; do \
		if test -f "$$p"; then \
			echo Installing $$p; \
			$(INSTALL) -m 0755 $$p $(LIBDIR)/plugins/; \
		fi \
	done

#TODO:
# configure plugins.  Or not. Better done under the direction of the installer
# or the packager.

install-async-prime: install-async

install-async:
	mkdir -p $(LIBDIR)
	$(INSTALL) -m 0755 build/node/_bin/munin-async $(LIBDIR)/
	$(INSTALL) -m 0755 build/node/_bin/munin-asyncd $(LIBDIR)/

install-node-prime: install-node-pre install-node

install-node-pre: build/node/munin-node.conf install-pre
	test -f "$(CONFDIR)/munin-node.conf" || $(INSTALL) -m 0644 build/node/munin-node.conf $(CONFDIR)/


install-common-prime: build-common install-common


install-man: build-man $(MAKEFILES)
	mkdir -p $(MANDIR)/man1 $(MANDIR)/man5 $(MANDIR)/man8
	$(INSTALL) -m 0644 build/doc/munin-node.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin-update.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-limits.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-graph.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-html.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-cron.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-check.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin.8 $(MANDIR)/man8/


install-doc: build-doc
	mkdir -p $(DOCDIR)/resources
	$(INSTALL) -m 0644 README $(DOCDIR)/
	$(INSTALL) -m 0644 COPYING $(DOCDIR)/
	$(INSTALL) -m 0644 build/resources/* $(DOCDIR)/resources

######################################################################

# Dummy rule to enable parallel building
infiles: $(INFILES)

build: infiles build-master build-common build-node build-plugins $(JAVA_BUILD) build-man build-confvar-substitution-stamp

build/%: %.in
	@echo "$< -> $@"
	@mkdir -p build/`dirname $<`
	@sed -e 's|@@PREFIX@@|$(PREFIX)|g' \
		-e 's|@@CONFDIR@@|$(CONFDIR)|g' \
		-e 's|@@BINDIR@@|$(BINDIR)|g' \
		-e 's|@@SBINDIR@@|$(SBINDIR)|g' \
		-e 's|@@DOCDIR@@|$(DOCDIR)|g' \
		-e 's|@@LIBDIR@@|$(LIBDIR)|g' \
		-e 's|@@MANDIR@@|$(MANDIR)|g' \
		-e 's|@@LOGDIR@@|$(LOGDIR)|g' \
		-e 's|@@HTMLDIR@@|$(HTMLDIR)|g' \
		-e 's|@@DBDIR@@|$(DBDIR)|g' \
		-e 's|@@STATEDIR@@|$(STATEDIR)|g' \
		-e 's|@@SPOOLDIR@@|$(SPOOLDIR)|g' \
		-e 's|@@PERL@@|$(PERL)|g' \
		-e 's|@@PERLLIB@@|$(PERLLIB)|g' \
		-e 's|@@PYTHON@@|$(PYTHON)|g' \
		-e 's|@@RUBY@@|$(RUBY)|g' \
		-e 's|@@JAVARUN@@|$(JAVARUN)|g' \
		-e 's|@@JAVALIBDIR@@|$(JAVALIBDIR)|g' \
		-e 's|@@OSTYPE@@|$(OSTYPE)|g' \
		-e 's|@@HOSTNAME@@|$(HOSTNAME)|g' \
		-e 's|@@MKTEMP@@|$(MKTEMP)|g' \
		-e 's|@@VERSION@@|$(VERSION)|g' \
		-e 's|@@PLUGSTATE@@|$(PLUGSTATE)|g' \
		-e 's|@@CGIDIR@@|$(CGIDIR)|g' \
		-e 's|@@CGITMPDIR@@|$(CGITMPDIR)|g' \
		-e 's|@@USER@@|$(USER)|g' \
		-e 's|@@GROUP@@|$(GROUP)|g' \
		-e 's|@@PLUGINUSER@@|$(PLUGINUSER)|g' \
		-e 's|@@GOODSH@@|$(GOODSH)|g' \
		-e 's|@@BASH@@|$(BASH)|g' \
		-e 's|@@HASSETR@@|$(HASSETR)|g' \
		$< > $@;


build-confvar-substitution-stamp: $(CONFVAR_SUBSTITUTION_DEP_FILES)
	$(MAKE) substitute-confvar-inline
	touch build-confvar-substitution-stamp


$(CONFVAR_SUBSTITUTION_DEP_FILES): build-master build-node build-man


substitute-confvar-inline:
	perl -p -i -e 's|\@\@PREFIX\@\@|$(PREFIX)|g;' \
		-e 's|\@\@CONFDIR\@\@|$(CONFDIR)|g;' \
		-e 's|\@\@BINDIR\@\@|$(BINDIR)|g;' \
		-e 's|\@\@SBINDIR\@\@|$(SBINDIR)|g;' \
		-e 's|\@\@DOCDIR\@\@|$(DOCDIR)|g;' \
		-e 's|\@\@LIBDIR\@\@|$(LIBDIR)|g;' \
		-e 's|\@\@MANDIR\@\@|$(MANDIR)|g;' \
		-e 's|\@\@LOGDIR\@\@|$(LOGDIR)|g;' \
		-e 's|\@\@HTMLDIR\@\@|$(HTMLDIR)|g;' \
		-e 's|\@\@DBDIR\@\@|$(DBDIR)|g;' \
		-e 's|\@\@STATEDIR\@\@|$(STATEDIR)|g;' \
		-e 's|\@\@SPOOLDIR\@\@|$(SPOOLDIR)|g;' \
		-e 's|\@\@PERL\@\@|$(PERL)|g;' \
		-e 's|\@\@PERLLIB\@\@|$(PERLLIB)|g;' \
		-e 's|\@\@PYTHON\@\@|$(PYTHON)|g;' \
		-e 's|\@\@RUBY\@\@|$(RUBY)|g;' \
		-e 's|\@\@JAVARUN\@\@|$(JAVARUN)|g;' \
		-e 's|\@\@JAVALIBDIR\@\@|$(JAVALIBDIR)|g;' \
		-e 's|\@\@OSTYPE\@\@|$(OSTYPE)|g;' \
		-e 's|\@\@HOSTNAME\@\@|$(HOSTNAME)|g;' \
		-e 's|\@\@MKTEMP\@\@|$(MKTEMP)|g;' \
		-e 's|\@\@VERSION\@\@|$(VERSION)|g;' \
		-e 's|\@\@PLUGSTATE\@\@|$(PLUGSTATE)|g;' \
		-e 's|\@\@CGIDIR\@\@|$(CGIDIR)|g;' \
		-e 's|\@\@USER\@\@|$(USER)|g;' \
		-e 's|\@\@GROUP\@\@|$(GROUP)|g;' \
		-e 's|\@\@PLUGINUSER\@\@|$(PLUGINUSER)|g;' \
		-e 's|\@\@GOODSH\@\@|$(GOODSH)|g;' \
		-e 's|\@\@BASH\@\@|$(BASH)|g;' \
		-e 's|\@\@HASSETR\@\@|$(HASSETR)|g;' \
		$(CONFVAR_SUBSTITUTION_FILES)


build-common-pre: common/Build
	cd common && $(PERL) Build code


# The target needs an update, if the latest substitution stamp is older then the generated
# Defaults.pm. This can happen, if:
#     * the generated Defaults.pm is missing
#     * or "build-common-pre" caused an update of its source file (thus regenerated Defaults.pm)
build-common-defaults-stamp: common/blib/lib/Munin/Common/Defaults.pm
	$(MAKE) substitute-build-defaults-inline
	@# We need the stamp file, due to the inline nature of this build step. Otherwise it would
	@# be run again during "install" - which would mess up the paths substituted in that step.
	touch build-common-defaults-stamp


# The "build-common-defaults-stamp" needs a way to generate the (non-substituted) defaults file
# during its first run.  Afterwards its content is sustituted due to the absence of the
# "build-common-defaults-stamp" file.
common/blib/lib/Munin/Common/Defaults.pm: build-common-pre


substitute-build-defaults-inline:
	rm -f common/blib/lib/Munin/Common/Defaults.pm
	$(PERL) -pe 's{(PREFIX\s+=\s).*}{\1q{$(PREFIX)};}x; \
		s{(CONFDIR\s+=\s).*}{\1q{$(CONFDIR)};}x; \
		s{(BINDIR\s+=\s).*}{\1q{$(BINDIR)};}x; \
		s{(SBINDIR\s+=\s).*}{\1q{$(SBINDIR)};}x; \
		s{(DOCDIR\s+=\s).*}{\1q{$(DOCDIR)};}x; \
		s{(LIBDIR\s+=\s).*}{\1q{$(LIBDIR)};}x; \
		s{(MANDIR\s+=\s).*}{\1q{$(MANDIR)};}x; \
		s{(LOGDIR\s+=\s).*}{\1q{$(LOGDIR)};}x; \
		s{(HTMLDIR\s+=\s).*}{\1q{$(HTMLDIR)};}x; \
		s{(DBDIR\s+=\s).*}{\1q{$(DBDIR)};}x; \
		s{(STATEDIR\s+=\s).*}{\1q{$(STATEDIR)};}x; \
		s{(SPOOLDIR\s+=\s).*}{\1q{$(SPOOLDIR)};}x; \
		s{(PERL\s+=\s).*}{\1q{$(PERL)};}x; \
		s{(PERLLIB\s+=\s).*}{\1q{$(PERLLIB)};}x; \
		s{(PYTHON\s+=\s).*}{\1q{$(PYTHON)};}x; \
		s{(RUBY\s+=\s).*}{\1q{$(RUBY)};}x; \
		s{(OSTYPE\s+=\s).*}{\1q{$(OSTYPE)};}x; \
		s{(HOSTNAME\s+=\s).*}{\1q{$(HOSTNAME)};}x; \
		s{(MKTEMP\s+=\s).*}{\1q{$(MKTEMP)};}x; \
		s{(VERSION\s+=\s).*}{\1q{$(VERSION)};}x; \
		s{(PLUGSTATE\s+=\s).*}{\1q{$(PLUGSTATE)};}x; \
		s{(CGIDIR\s+=\s).*}{\1q{$(CGIDIR)};}x; \
		s{(USER\s+=\s).*}{\1q{$(USER)};}x; \
		s{(GROUP\s+=\s).*}{\1q{$(GROUP)};}x; \
		s{(PLUGINUSER\s+=\s).*}{\1q{$(PLUGINUSER)};}x; \
		s{(GOODSH\s+=\s).*}{\1q{$(GOODSH)};}x; \
		s{(BASH\s+=\s).*}{\1q{$(BASH)};}x; \
		s{(HASSETR\s+=\s).*}{\1q{$(HASSETR)};}x;' \
		common/lib/Munin/Common/Defaults.pm >common/blib/lib/Munin/Common/Defaults.pm


build-doc: build-doc-stamp $(MAKEFILES)

build-doc-stamp:
	touch build-doc-stamp
	mkdir -p build/doc

build-man: build-man-stamp $(MAKEFILES)

build-man-stamp: $(INFILES)
	mkdir -p build/doc
	for f in $(MAN8); do \
		pod2man --section=8 --release=$(RELEASE) --center=$(MANCENTER) build/"$$f" > build/doc/`basename $$f`.8; \
	done
	for f in $(PODMAN8); do \
		pod2man --section=8 --release=$(RELEASE) --center=$(MANCENTER) "$$f".pod > build/doc/`basename $$f .pod`.8; \
	done
	for f in $(PODMAN5); do \
		pod2man --section=5 --release=$(RELEASE) --center=$(MANCENTER) "$$f".pod > build/doc/`basename $$f .pod`.5; \
	done
	touch build-man-stamp


build-plugins-java: build/plugins/javalib/munin-jmx-plugins.jar

build/plugins/javalib/munin-jmx-plugins.jar: $(CLASSFILES)
	cd build/plugins/javalib && $(JAR) cf munin-jmx-plugins.jar org/munin/plugin/jmx

build-java-stamp:
	mkdir -p build/plugins/javalib
	touch build-java-stamp

build/%.class: %.class build-java-stamp
	@echo "Compiling $*"

######################################################################
# DIST RULES

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

suse-pre:
	(! grep MAINTAINER Makefile.config)
	@for file in `find dists/suse/ -type f -name '*.in'`; do \
		destname=`echo $$file | sed 's/.in$$//'`; \
		echo Generating $$destname..; \
		sed -e 's|@@VERSION@@|$(VERSION)|g' \
		$$file > $$destname; \
	done
	-cp dists/tarball/plugins.conf .
#	(cd ..; ln -s munin munin-$(VERSION))

suse: suse-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -tb munin-$(RELEASE).tar.gz)

suse-src: suse-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -ts munin-$(RELEASE).tar.gz)

source_dist: clean
	(! grep MAINTAINER Makefile.config)
	(cd .. && ln -s $(DIR) munin-$(VERSION))
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd .. && rm munin-$(VERSION))

######################################################################

ifeq ($(MAKELEVEL),0)
clean: clean-node clean-master clean-plugins clean-common
else
clean:
endif
	-rm -rf build
	-rm -f build-stamp
	-rm -f build-doc-stamp
	-rm -f build-man-stamp
	-rm -f build-java-stamp
	-rm -f build-confvar-substitution-stamp
	-rm -f build-common-defaults-stamp
	-rm -rf t/install

	-rm -f dists/redhat/munin.spec
	-rm -f dists/suse/munin.spec


######################################################################

test: test-common test-master test-node test-plugins

ifeq ($(MAKELEVEL),0)
# Re-exec make with the test config
old-test: t/*.t
	$(MAKE) $@ CONFIG=t/Makefile.config
else
test_plugins = id_default id_root env
old-test: t/*.t t/install $(addprefix $(CONFDIR)/plugins/,$(test_plugins))
	@for test in t/*.t; do \
		echo -n "$$test: "; \
		PERL5LIB=$(PERLLIB) $(PERL) $$test;\
	done
endif

node-monkeywrench: install-node
	rm -rf $(CONFDIR)/plugins
	rm -rf $(LIBDIR)/plugins
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(CONFDIR)/plugins
	cp monkeywrench/plugin-break*_ $(LIBDIR)/plugins/
	$(SBINDIR)/munin-node-configure --suggest
	echo 'Done?'

t/install:
	$(MAKE) clean install-node-prime install-node-plugins CONFIG=t/Makefile.config INSTALL_PLUGINS=test


######################################################################

# This builds */Build from Build.PL
%/Build: %/Build.PL
	cd $* && $(PERL) -I. Build.PL

build-%: %/Build
	cd $* && $(PERL) Build

build-common: build-common-defaults-stamp

# BUG: the Build script writes files under PWD when it does "install"
# can't seem to find a way to persuade it to write otherwhere.
install-%: %/Build
	cd $* && $(PERL) Build install \
		--install_path lib=$(PERLLIB) \
		--install_path bin=$(BINDIR) \
		--install_path script=$(BINDIR) \
		--install_path sbin=$(SBINDIR) \
		--install_path bindoc=$(MANDIR)/man1 \
		--install_path libdoc=$(MANDIR)/man3

test-%: %/Build
	cd $* && $(PERL) Build test --verbose=0


.PHONY: lint lint-plugins lint-spelling
lint: lint-plugins lint-spelling

lint-plugins:
	@# SC1008: ignore our weird shebang (substituted later)
	@# SC1090: ignore sourcing of files with variable in path
	@# SC2009: do not complain about "ps ... | grep" calls (may be platform specific)
	@# SC2126: tolerate "grep | wc -l" (simple and widespread) instead of "grep -c"
	@# SC2230: do not complain about "which" (instead of "command -v")
	# TODO: fix the remaining shellcheck issues for the missing platforms:
	#       aix, darwin, netbsd, sunos
	#       (these require tests with their specific shell implementations)
	find plugins/node.d/ \
			plugins/node.d.cygwin/ \
			plugins/node.d.debug/ \
			plugins/node.d.linux/ -type f -print0 \
		| xargs -0 grep -l --null "@@GOODSH@@" \
			| xargs -0 shellcheck --exclude=SC1008,SC1090,SC2009,SC2126,SC2230,SC2239 --shell dash
	find plugins/ -type f -print0 \
		| xargs -0 grep -l --null "@@BASH@@" \
			| xargs -0 shellcheck --exclude=SC1008,SC1090,SC2009,SC2126,SC2230,SC2239 --shell bash
	find plugins/ -type f -print0 \
		| xargs -0 grep -l --null "@@PYTHON@@" \
			| xargs -0 $(PYTHON_LINT_CALL)
	# TODO: perl plugins currently fail with perlcritic

lint-spelling:
	# codespell misdetections may be ignored by adding the full line of text to the file .codespell.exclude
	find . -type f -print0 \
		| grep --null-data -vE '^\./(\.git|\.pc|doc/_build|blib|.*/blib|build|sandbox|web/static/js|contrib/plugin-gallery/www/static/js)/' \
		| grep --null-data -vE '\.(svg|png|gif|ico|css|woff|woff2|ttf|eot)$$' \
		| grep --null-data -vE '^\./(contrib|master|node|resources|plugins)/' \
		| xargs -0 -r codespell --exclude-file=.codespell.exclude

clean-%: %/Build build-common-defaults-stamp
	cd $* && $(PERL) Build realclean
