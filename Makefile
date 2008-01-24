# Gnu make only.  Seriously.
# $Id$

# Defaults/paths from this file
include Makefile.config

RELEASE          = $(shell cat RELEASE)
INSTALL_PLUGINS ?= "auto manual contrib snmpauto"
INSTALL          = ./install-sh
DIR              = $(shell /bin/pwd | sed 's/^.*\///')
INFILES		 = $(shell find . -name '*.in')
PLUGINS		 = $(wildcard node/node.d.$(OSTYPE)/* node/node.d/*)
MANCENTER        = "Munin Documentation"
MAN8		 = node/munin-node node/munin-run \
			node/munin-node-configure-snmp \
			node/munin-node-configure \
			server/munin-graph server/munin-update \
			server/munin-limits server/munin-html
PODMAN8          = server/munin-cron
PODMAN5          = server/munin.conf node/munin-node.conf

default: build

install: install-main install-node install-node-plugins install-man

uninstall: uninstall-main

# This removes the installed config so that the next install-pass installs
# a new config.  Target suitable for maintainers
unconfig:
	rm -f $(HTMLDIR)/.htaccess
	rm -f $(CONFDIR)/munin.conf

install-main: build
	$(CHECKUSER)
	mkdir -p $(CONFDIR)/templates
	mkdir -p $(LIBDIR)
	mkdir -p $(BINDIR)
	mkdir -p $(PERLLIB)

	mkdir -p $(LOGDIR)
	mkdir -p $(STATEDIR)
	mkdir -p $(HTMLDIR)
	mkdir -p $(DBDIR)
	mkdir -p $(CGIDIR)

	$(CHOWN) $(USER) $(LOGDIR) $(STATEDIR) $(RUNDIR) $(HTMLDIR) $(DBDIR)

	for p in build/server/*.tmpl; do    		         \
		$(INSTALL) -m 0644 "$$p" $(CONFDIR)/templates/ ; \
	done
	$(INSTALL) -m 0644 server/logo.png $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/style.css $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/definitions.html $(CONFDIR)/templates/
	$(INSTALL) -m 0755 server/VeraMono.ttf $(LIBDIR)/
	$(INSTALL) -m 0644 resources/favicon.ico $(HTMLDIR)/
	test -f $(HTMLDIR)/.htaccess || $(INSTALL) -m 0644 build/server/munin-htaccess $(HTMLDIR)/.htaccess
	test -f "$(CONFDIR)/munin.conf"  || $(INSTALL) -m 0644 build/server/munin.conf $(CONFDIR)/
	$(INSTALL) -m 0755 build/server/munin-cron $(BINDIR)/
	$(INSTALL) -m 0755 build/server/munin-update $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-graph $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-html $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-limits $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-cgi-graph $(CGIDIR)/
	$(INSTALL) -m 0644 build/server/Munin.pm $(PERLLIB)/

uninstall-main: build
	for p in build/server/*.tmpl; do    	    \
		rm -f $(CONFDIR)/templates/"$$p"  ; \
	done
	rm -f $(CONFDIR)/templates/logo.png
	rm -f $(CONFDIR)/templates/style.css
	rm -f $(CONFDIR)/templates/definitions.html
	rm -f $(HTMLDIR)/.htaccess

	rm -f $(CONFDIR)/munin.conf 

	rm -f $(BINDIR)/munin-cron 

	rm -f $(LIBDIR)/munin-update
	rm -f $(LIBDIR)/munin-graph
	rm -f $(LIBDIR)/munin-html
	rm -f $(LIBDIR)/munin-limits
	rm -f $(CGIDIR)/munin-cgi-graph

	rm -f $(PERLLIB)/Munin.pm 
	-rmdir $(CONFDIR)/templates
	-rmdir $(CONFDIR)
	-rmdir $(LIBDIR)
	-rmdir $(BINDIR)

	-rmdir $(LOGDIR)
	-rmdir $(STATEDIR)
	-rmdir $(HTMLDIR)
	-rmdir $(DBDIR)
	-rmdir $(CGIDIR)

install-node: build install-node-non-snmp install-node-snmp
	echo Done.

uninstall-node: uninstall-node-non-snmp uninstall-node-snmp
	echo Undone.

install-node-snmp: build
	$(INSTALL) -m 0755 build/node/munin-node-configure-snmp $(SBINDIR)/

uninstall-node-snmp: build
	rm -f $(SBINDIR)/munin-node-configure-snmp
	-rmdir $(SBINDIR)

install-node-non-snmp: build
	$(CHECKGROUP)
	mkdir -p $(CONFDIR)/plugins
	mkdir -p $(CONFDIR)/plugin-conf.d
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(SBINDIR)
	mkdir -p $(PERLLIB)/Munin/Plugin

	mkdir -p $(LOGDIR)
	mkdir -p $(STATEDIR)
	mkdir -p $(PLUGSTATE)

	$(CHGRP) $(GROUP) $(PLUGSTATE)
	$(CHMOD) 775 $(PLUGSTATE)
	$(CHMOD) 755 $(CONFDIR)/plugin-conf.d

	$(INSTALL) -m 0755 build/node/munin-node $(SBINDIR)/
	$(INSTALL) -m 0755 build/node/munin-node-configure $(SBINDIR)/
	test -f "$(CONFDIR)/munin-node.conf" || $(INSTALL) -m 0644 build/node/munin-node.conf $(CONFDIR)/
	$(INSTALL) -m 0755 build/node/munin-run $(SBINDIR)/

uninstall-node-non-snmp: build
	rm -f $(SBINDIR)/munin-node 
	rm -f $(SBINDIR)/munin-node-configure
	rm -f $(CONFDIR)/munin-node.conf 
	rm -f $(SBINDIR)/munin-run
	-rmdir $(CONFDIR)/plugin-conf.d
	-rmdir $(CONFDIR)
	-rmdir $(SBINDIR)


# ALWAYS DO THE OS SPECIFIC PLUGINS LAST! THAT WAY THEY OVERWRITE THE
# GENERIC ONES

# Some HP-UX plugins needs *.adv support files in LIBDIR
install-node-plugins: build $(PLUGINS) Makefile Makefile.config
	for p in build/node/node.d/* build/node/node.d.$(OSTYPE)/* ; do \
	    if test -f "$$p" ; then                                    \
		family=`sed -n 's/^#%# family=\(.*\)$$/\1/p' $$p`;     \
		test "$$family" || family=contrib;                     \
		if echo $(INSTALL_PLUGINS) |                           \
		   grep $$family >/dev/null; then 	               \
			echo Installing $$p;                           \
			$(INSTALL) -m 0755 $$p $(LIBDIR)/plugins/;     \
		fi;                                                    \
	    fi                                                         \
	done
	-mv $(LIBDIR)/plugins/*.adv $(LIBDIR)
	-mkdir -p $(PLUGSTATE)
	$(CHOWN) $(PLUGINUSER):$(GROUP) $(PLUGSTATE)
	$(CHMOD) 0664 $(PLUGSTATE)
	$(INSTALL) -m 0644 build/node/plugins.history $(LIBDIR)/plugins/
	$(INSTALL) -m 0644 build/node/plugin.sh $(LIBDIR)/plugins/
	mkdir -p $(PERLLIB)/Munin
	$(INSTALL) -m 0644 build/node/Plugin.pm $(PERLLIB)/Munin/

uninstall-node-plugins: build $(PLUGINS)
	for p in build/node/node.d.$(OSTYPE)/* build/node/node.d/*; do \
	    rm -f $(LIBDIR)/plugins/`basename $$p` \
	done
	rm -f $(LIBDIR)/plugins/plugins.history
	rm -f $(LIBDIR)/plugins/plugin.sh
	-rm -f $(LIBDIR)/*.adv

#TODO:
# configure plugins.  Or not. Better done under the direction of the installer
# or the packager.

install-man: build-man Makefile Makefile.config
	mkdir -p $(MANDIR)/man1 $(MANDIR)/man5 $(MANDIR)/man8
	$(INSTALL) -m 0644 build/doc/munin-node.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin-node.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-node-configure.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-node-configure-snmp.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-run.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-graph.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-update.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-limits.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-html.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-cron.8 $(MANDIR)/man8/

uninstall-man: build-man
	rm -f $(MANDIR)/man5/munin-node.conf.5 
	rm -f $(MANDIR)/man5/munin.conf.5 
	rm -f $(MANDIR)/man8/munin-node.8
	rm -f $(MANDIR)/man8/munin-node-configure.8 
	rm -f $(MANDIR)/man8/munin-node-configure-snmp.8
	rm -f $(MANDIR)/man8/munin-run.8
	rm -f $(MANDIR)/man8/munin-graph.8 
	rm -f $(MANDIR)/man8/munin-update.8 
	rm -f $(MANDIR)/man8/munin-limits.8
	rm -f $(MANDIR)/man8/munin-html.8
	rm -f $(MANDIR)/man8/munin-cron.8 
	-rmdir $(MANDIR)/man1 $(MANDIR)/man5 $(MANDIR)/man8 $(MANDIR)

install-doc: build-doc
	mkdir -p $(DOCDIR)/resources
	$(INSTALL) -m 0644 README $(DOCDIR)/
	$(INSTALL) -m 0644 COPYING $(DOCDIR)/
	$(INSTALL) -m 0644 build/resources/* $(DOCDIR)/resources

uninstall-doc: build-doc
	rm -rf $(DOCDIR)

build: build-stamp

# Recursive pattern rule needed.
# %: %.in Makefile Makefile.config

build-stamp: $(INFILES) Makefile Makefile.config
	touch build-stamp
	rm -rf build
	@for file in $(INFILES); do			\
		destname=`echo $$file | sed 's/.in$$//'`;		\
		echo Generating build/$$destname..;			\
		mkdir -p build/`dirname $$file`;			\
		sed -e 's|@@PREFIX@@|$(PREFIX)|g'			\
		    -e 's|@@CONFDIR@@|$(CONFDIR)|g'			\
		    -e 's|@@BINDIR@@|$(BINDIR)|g'			\
		    -e 's|@@SBINDIR@@|$(SBINDIR)|g'			\
		    -e 's|@@DOCDIR@@|$(DOCDIR)|g'			\
		    -e 's|@@LIBDIR@@|$(LIBDIR)|g'			\
		    -e 's|@@MANDIR@@|$(MANDIR)|g'			\
		    -e 's|@@LOGDIR@@|$(LOGDIR)|g'			\
		    -e 's|@@HTMLDIR@@|$(HTMLDIR)|g'			\
		    -e 's|@@DBDIR@@|$(DBDIR)|g'				\
		    -e 's|@@STATEDIR@@|$(STATEDIR)|g'			\
		    -e 's|@@PERL@@|$(PERL)|g'				\
		    -e 's|@@PERLLIB@@|$(PERLLIB)|g'			\
		    -e 's|@@PYTHON@@|$(PYTHON)|g'			\
		    -e 's|@@OSTYPE@@|$(OSTYPE)|g'			\
		    -e 's|@@HOSTNAME@@|$(HOSTNAME)|g'			\
		    -e 's|@@MKTEMP@@|$(MKTEMP)|g'			\
		    -e 's|@@VERSION@@|$(VERSION)|g'			\
		    -e 's|@@PLUGSTATE@@|$(PLUGSTATE)|g'			\
		    -e 's|@@CGIDIR@@|$(CGIDIR)|g'			\
		    -e 's|@@USER@@|$(USER)|g'				\
		    -e 's|@@GROUP@@|$(GROUP)|g'				\
		    -e 's|@@PLUGINUSER@@|$(PLUGINUSER)|g'		\
		    -e 's|@@GOODSH@@|$(GOODSH)|g'			\
		    -e 's|@@BASH@@|$(BASH)|g'				\
		    -e 's|@@HASSETR@@|$(HASSETR)|g'			\
		    $$file > build/$$destname;				\
	done

build-doc: build-doc-stamp Makefile Makefile.config

build-doc-stamp:
	touch build-doc-stamp
	mkdir -p build/doc

build-man: build-man-stamp 

build-man-stamp: build Makefile Makefile.config
	touch build-man-stamp
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


deb:
	(! grep MAINTAINER Makefile.config)
	-rm debian
	-ln -s dists/debian
	fakeroot debian/rules binary

rpm-pre:
	(! grep MAINTAINER Makefile.config)
	@for file in `find dists/redhat/ -type f -name '*.in'`; do			\
		destname=`echo $$file | sed 's/.in$$//'`;		\
		echo Generating $$destname..;				\
		sed -e 's|@@VERSION@@|$(VERSION)|g'			\
		    $$file > $$destname;				\
	done
	-cp dists/tarball/plugins.conf .
#	(cd ..; ln -s munin munin-$(VERSION))

rpm: rpm-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -tb munin_$(RELEASE).tar.gz)

rpm-src: rpm-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin-$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -ts munin-$(RELEASE).tar.gz)

suse-pre:
	(! grep MAINTAINER Makefile.config)
	@for file in `find dists/suse/ -type f -name '*.in'`; do                \
		destname=`echo $$file | sed 's/.in$$//'`;               \
		echo Generating $$destname..;                           \
		sed -e 's|@@VERSION@@|$(VERSION)|g'                     \
		$$file > $$destname;                                \
	done
	-cp dists/tarball/plugins.conf .
#	(cd ..; ln -s munin munin-$(VERSION))

suse: suse-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -tb munin-$(RELEASE).tar.gz)

suse-src: suse-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -ts munin-$(RELEASE).tar.gz)

clean:
ifeq ($(MAKELEVEL),0)
	-rm -f debian
	-ln -sf dists/debian
	-fakeroot debian/rules clean
	-rm -f debian
endif
	-rm -rf build
	-rm -f build-stamp
	-rm -f build-doc-stamp
	-rm -f build-man-stamp
	-rm -rf t/install

	-rm -f dists/redhat/munin.spec
	-rm -f dists/suse/munin.spec

source_dist: clean
	(! grep MAINTAINER Makefile.config)
	(cd .. && ln -s $(DIR) munin-$(VERSION))
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd .. && rm munin-$(VERSION))

ifeq ($(MAKELEVEL),0)
# Re-exec make with the test config
test: t/*.t
	$(MAKE) $@ CONFIG=t/Makefile.config
else
test_plugins = id_default id_root env
test: t/*.t t/install $(addprefix $(CONFDIR)/plugins/,$(test_plugins))
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
	$(MAKE) clean install-node install-node-plugins CONFIG=t/Makefile.config INSTALL_PLUGINS=test

.PHONY: install install-main install-node install-doc install-man build build-doc deb clean source_dist test
