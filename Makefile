#! /usr/bin/make -f

DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
include $(CONFIG)

RELEASE          = $(shell cat RELEASE)
INSTALL_PLUGINS ?= "auto manual contrib snmpauto"
INSTALL          = ./install-sh

default: build

install: install-main install-node install-node-plugins install-doc install-man

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

	$(CHOWN) $(USER) $(LOGDIR) $(STATEDIR) $(RUNDIR) $(HTMLDIR) $(DBDIR)

	for p in build/server/*.tmpl; do    		              \
		$(INSTALL) -m 0644 "$$p" $(CONFDIR)/templates/ ; \
	done
	$(INSTALL) -m 0644 server/logo.png $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/style.css $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/definitions.html $(CONFDIR)/templates/

	test -f "$(CONFDIR)/munin.conf"  || $(INSTALL) -m 0644 build/server/munin.conf $(CONFDIR)/

	$(INSTALL) -m 0755 build/server/munin-cron $(BINDIR)/

	$(INSTALL) -m 0755 build/server/munin-update $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-graph $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-html $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-limits $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-cgi-graph $(CGIDIR)/

	$(INSTALL) -m 0644 build/server/Munin.pm $(PERLLIB)/

install-node: build
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
	$(INSTALL) -m 0755 build/node/munin-node-configure-snmp $(SBINDIR)/
	test -f "$(CONFDIR)/munin-node.conf" || $(INSTALL) -m 0644 build/node/munin-node.conf $(CONFDIR)/
	$(INSTALL) -m 0755 build/node/munin-run $(SBINDIR)/
	
#	$(INSTALL) -m 0644 build/node/SNMP.pm $(PERLLIB)/Munin/Plugin/

install-node-plugins: build
	for p in build/node/node.d.$(OSTYPE)/* build/node/node.d/*; do    		\
		if test -f "$$p" ; then                                     		\
			family=`sed -n 's/^#%# family=\(.*\)$$/\1/p' $$p`;  		\
			test "$$family" || family=contrib;                  		\
			if echo $(INSTALL_PLUGINS) | grep $$family >/dev/null; then 	\
				test -f "$(LIBDIR)/plugins/`basename $$p`"		\
				|| $(INSTALL) -m 0755 $$p $(LIBDIR)/plugins/;    		\
			fi;                                                 		\
		fi                                                          		\
	done
	$(INSTALL) -m 0644 build/node/plugins.history $(LIBDIR)/plugins/

	#TODO:
	#configure plugins.

install-man: build-man
	mkdir -p $(MANDIR)/man1 $(MANDIR)/man5 $(MANDIR)/man8
	$(INSTALL) -m 0644 build/doc/munin-node.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin-node.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-run.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-graph.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-update.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-limits.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-html.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-cron.8 $(MANDIR)/man8/

install-doc: build-doc
	mkdir -p $(DOCDIR)
	$(INSTALL) -m 0644 build/doc/munin-doc.html $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-doc.pdf $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-doc.txt $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-faq.html $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-faq.pdf $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-faq.txt $(DOCDIR)/
	$(INSTALL) -m 0644 README.* $(DOCDIR)/
	$(INSTALL) -m 0644 COPYING $(DOCDIR)/
	$(INSTALL) -m 0644 node/node.d/README $(DOCDIR)/README.plugins

build: build-stamp

build-stamp:
	@for file in `find . -type f -name '*.in'`; do			\
		destname=`echo $$file | sed 's/.in$$//'`;		\
		echo Generating $$destname..;				\
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
		    -e 's|@@PYTHON@@|$(PYTHON)|g'				\
		    -e 's|@@OSTYPE@@|$(OSTYPE)|g'				\
		    -e 's|@@HOSTNAME@@|$(HOSTNAME)|g'			\
		    -e 's|@@VERSION@@|$(VERSION)|g'			\
		    -e 's|@@PLUGSTATE@@|$(PLUGSTATE)|g'			\
		    -e 's|@@CGIDIR@@|$(CGIDIR)|g'			\
		    $$file > build/$$destname;				\
	done
	touch build-stamp

build-doc: build-doc-stamp

build-doc-stamp:
	mkdir -p build/doc
	-htmldoc munin-doc-base.html > build/doc/munin-doc.html
	-htmldoc -t pdf --webpage build/doc/munin-doc.html > build/doc/munin-doc.pdf
	-html2text -style pretty -nobs build/doc/munin-doc.html > build/doc/munin-doc.txt

	-htmldoc munin-faq-base.html > build/doc/munin-faq.html
	-htmldoc -t pdf --webpage build/doc/munin-faq.html > build/doc/munin-faq.pdf
	-html2text -style pretty -nobs build/doc/munin-faq.html > build/doc/munin-faq.txt

	touch build-doc-stamp

build-man: build-man-stamp

build-man-stamp:
	mkdir -p build/doc
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		node/munin-node.in > build/doc/munin-node.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		node/munin-run.in > build/doc/munin-run.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		node/munin-node-configure.in > build/doc/munin-node-configure.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin-graph.in > build/doc/munin-graph.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin-update.in > build/doc/munin-update.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin-limits.in > build/doc/munin-limits.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin-html.in > build/doc/munin-html.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin-cron.pod > build/doc/munin-cron.8
	pod2man  --section=5 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin.conf.pod > build/doc/munin.conf.5
	pod2man  --section=5 --release=$(RELEASE) --center="Munin Documentation" \
		node/munin-node.conf.pod > build/doc/munin-node.conf.5

	touch build-man-stamp

deb:
	-rm debian
	-ln -s dists/debian
	fakeroot debian/rules binary

rpm-pre:
	@for file in `find dists/redhat/ -type f -name '*.in'`; do			\
		destname=`echo $$file | sed 's/.in$$//'`;		\
		echo Generating $$destname..;				\
		sed -e 's|@@VERSION@@|$(VERSION)|g'			\
		    $$file > $$destname;				\
	done
	-cp dists/tarball/plugins.conf .
	(cd ..; ln -s munin munin-$(VERSION))

rpm: rpm-pre
	tar -C .. --dereference --exclude CVS  -cvzf ../munin-$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpm -tb munin-$(RELEASE).tar.gz)
	
rpm-src: rpm-pre
	tar -C .. --dereference --exclude CVS  -cvzf ../munin-$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpm -ts munin-$(RELEASE).tar.gz)

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

source_dist: clean
	(cd ..; ln -s munin munin-$(VERSION))
	tar -C .. --dereference --exclude CVS -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/

.PHONY: install install-main install-node install-doc install-man build build-doc deb clean source_dist
