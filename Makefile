#! /usr/bin/make -f

DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
include $(CONFIG)

RELEASE          = $(shell cat RELEASE)
INSTALL_PLUGINS ?= "auto manual contrib"
INSTALL          = ./install-sh

default: build

install: install-main install-eye install-eye-plugins install-doc

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

	$(INSTALL) -m 0644 server/*.tmpl $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/logo.gif $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/style.css $(CONFDIR)/templates/

	test -f "$(CONFDIR)/munin.conf"  || $(INSTALL) -m 0644 build/server/munin.conf $(CONFDIR)/

	$(INSTALL) -m 0755 build/server/munin-cron $(BINDIR)/

	$(INSTALL) -m 0755 build/server/munin-update $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-nagios $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-graph $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-html $(LIBDIR)/

	$(INSTALL) -m 0644 build/server/Munin.pm $(PERLLIB)/

install-node: build
	$(CHECKGROUP)
	mkdir -p $(CONFDIR)/plugins
	mkdir -p $(CONFDIR)/plugin-conf.d
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(SBINDIR)

	mkdir -p $(LOGDIR)
	mkdir -p $(STATEDIR)
	mkdir -p $(PLUGSTATE)

	$(CHGRP) $(GROUP) $(PLUGSTATE)
	$(CHMOD) 775 $(PLUGSTATE)
	$(CHMOD) 755 $(CONFDIR)/plugin-conf.d

	$(INSTALL) -m 0755 build/eye/munin-eye $(SBINDIR)/
	$(INSTALL) -m 0755 build/eye/munin-eye-configure $(SBINDIR)/
	test -f "$(CONFDIR)/munin-eye.conf" || $(INSTALL) -m 0644 build/eye/munin-eye.conf $(CONFDIR)/
	$(INSTALL) -m 0755 build/eye/munin-run $(SBINDIR)/

install-eye-plugins: build
	for p in build/eye/plugins.$(ARCH)/* build/eye/plugins/*; do    		\
		if test -f "$$p" ; then                                     		\
			family=`sed -n 's/^#%# family=\(.*\)$$/\1/p' $$p`;  		\
			test "$$family" || family=contrib;                  		\
			if echo $(INSTALL_PLUGINS) | grep $$family >/dev/null; then 	\
				test -f "$(LIBDIR)/plugins/`basename $$p`"		\
				|| $(INSTALL) -m 0755 $$p $(LIBDIR)/plugins/;    		\
			fi;                                                 		\
		fi                                                          		\
	done
	$(INSTALL) -m 0644 build/eye/plugins.history $(LIBDIR)/plugins/

	#TODO:
	#configure plugins.

install-doc: build-doc
	mkdir -p $(DOCDIR)
	mkdir -p $(MANDIR)/man1 $(MANDIR)/man5 $(MANDIR)/man8
	$(INSTALL) -m 0644 build/doc/node.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin-node.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-run.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-graph.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-update.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-nagios.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-html.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-cron.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-doc.* $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-faq.* $(DOCDIR)/
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
		    -e 's|@@ARCH@@|$(ARCH)|g'				\
		    -e 's|@@HOSTNAME@@|$(HOSTNAME)|g'			\
		    -e 's|@@VERSION@@|$(VERSION)|g'			\
		    -e 's|@@PLUGSTATE@@|$(PLUGSTATE)|g'			\
		    $$file > build/$$destname;				\
	done
	touch build-stamp

build-doc: build-doc-stamp

build-doc-stamp:
	mkdir -p build/doc
	htmldoc munin.html > build/doc/munin-doc.html
	htmldoc -t pdf --webpage build/doc/munin-doc.html > build/doc/munin-doc.pdf
	html2text -style pretty -nobs build/doc/munin-doc.html > build/doc/munin-doc.txt

	htmldoc munin-faq-base.html > build/doc/munin-faq.html
	htmldoc -t pdf --webpage build/doc/munin-faq.html > build/doc/munin-faq.pdf
	html2text -style pretty -nobs build/doc/munin-faq.html > build/doc/munin-faq.txt

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
		server/munin-html.in > build/doc/munin-html.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin-nagios.in > build/doc/munin-nagios.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin-cron.pod > build/doc/munin-cron.8
	pod2man  --section=5 --release=$(RELEASE) --center="Munin Documentation" \
		server/server.conf.pod > build/doc/server.conf.5
	pod2man  --section=5 --release=$(RELEASE) --center="Munin Documentation" \
		node/node.conf.pod > build/doc/node.conf.5

	touch build-doc-stamp

deb:
	-rm debian
	-ln -s dists/debian
	fakeroot debian/rules binary

rpm:
	-rm -rf dists/redhat/munin-* dists/redhat/noarch
	-dists/redhat/buildtargz.sh
	-rpmbuild \
		--define "_specdir dists/redhat"   \
		--define "_sourcedir dists/redhat" \
		--define "_srcrpmdir dists/redhat" \
                -bs dists/redhat/munin.spec

	-rpmbuild \
		--define "_rpmtopdir `pwd`/dists/redhat" \
		--define "_sourcedir %{_rpmtopdir}"      \
		--define "_builddir %{_rpmtopdir}"       \
		--define "_rpmdir %{_rpmtopdir}"         \
	        -bb dists/redhat/munin.spec

	-mv dists/redhat/*rpm ..
	-mv dists/redhat/noarch/*rpm ..
	-rm -rf dists/redhat/munin-* dists/redhat/noarch

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

source_dist: clean
	cp dists/tarball/plugins.conf .
	(cd ..; ln -s munin munin-$(VERSION))
	tar -C .. --dereference --exclude CVS --exclude dists -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/

.PHONY: install install-main install-eye install-doc build build-doc deb rpm clean source_dist
