#! /usr/bin/make -f

DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
include $(CONFIG)

RELEASE          = $(shell cat RELEASE)
INSTALL_PLUGINS ?= "auto manual contrib"
INSTALL          = ./install-sh

default: build

install: install-server install-client install-client-plugins install-doc

install-server: build
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

	test -f "$(CONFDIR)/server.conf"  || $(INSTALL) -m 0644 build/server/server.conf $(CONFDIR)/

	$(INSTALL) -m 0755 build/server/lrrd-cron $(BINDIR)/

	$(INSTALL) -m 0755 build/server/lrrd-update $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/lrrd-nagios $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/lrrd-graph $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/lrrd-html $(LIBDIR)/

	$(INSTALL) -m 0644 build/server/LRRD.pm $(PERLLIB)/

install-client: build
	$(CHECKGROUP)
	mkdir -p $(CONFDIR)/client.d
	mkdir -p $(CONFDIR)/client-conf.d
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(SBINDIR)

	mkdir -p $(LOGDIR)
	mkdir -p $(STATEDIR)
	mkdir -p $(PLUGSTATE)

	$(CHGRP) $(GROUP) $(PLUGSTATE)
	$(CHMOD) 775 $(PLUGSTATE)
	$(CHMOD) 755 $(CONFDIR)/client-conf.d

	$(INSTALL) -m 0755 build/client/lrrd-client $(SBINDIR)/
	$(INSTALL) -m 0755 build/client/lrrd-client-configure $(SBINDIR)/
	test -f "$(CONFDIR)/client.conf" || $(INSTALL) -m 0644 build/client/client.conf $(CONFDIR)/
	$(INSTALL) -m 0755 build/client/lrrd-run $(SBINDIR)/

install-client-plugins: build
	for p in build/client/lrrd.d.$(ARCH)/* build/client/lrrd.d/*; do    		\
		if test -f "$$p" ; then                                     		\
			family=`sed -n 's/^#%# family=\(.*\)$$/\1/p' $$p`;  		\
			test "$$family" || family=contrib;                  		\
			if echo $(INSTALL_PLUGINS) | grep $$family >/dev/null; then 	\
				test -f "$(LIBDIR)/plugins/`basename $$p`"		\
				|| $(INSTALL) -m 0755 $$p $(LIBDIR)/plugins/;    		\
			fi;                                                 		\
		fi                                                          		\
	done
	$(INSTALL) -m 0644 build/client/plugins.history $(LIBDIR)/plugins/

	#TODO:
	#configure plugins.

install-doc: build-doc
	mkdir -p $(DOCDIR)
	mkdir -p $(MANDIR)/man1 $(MANDIR)/man5 $(MANDIR)/man8
	$(INSTALL) -m 0644 build/doc/client.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/server.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/lrrd-client.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/lrrd-run.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/lrrd-graph.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/lrrd-update.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/lrrd-nagios.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/lrrd-html.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/lrrd-cron.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/lrrd-doc.* $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/lrrd-faq.* $(DOCDIR)/
	$(INSTALL) -m 0644 README.* $(DOCDIR)/
	$(INSTALL) -m 0644 COPYING $(DOCDIR)/
	$(INSTALL) -m 0644 client/lrrd.d/README $(DOCDIR)/README.plugins

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
	htmldoc lrrd.html > build/doc/lrrd-doc.html
	htmldoc -t pdf --webpage build/doc/lrrd-doc.html > build/doc/lrrd-doc.pdf
	html2text -style pretty -nobs build/doc/lrrd-doc.html > build/doc/lrrd-doc.txt

	htmldoc lrrd-faq-base.html > build/doc/lrrd-faq.html
	htmldoc -t pdf --webpage build/doc/lrrd-faq.html > build/doc/lrrd-faq.pdf
	html2text -style pretty -nobs build/doc/lrrd-faq.html > build/doc/lrrd-faq.txt

	pod2man  --section=8 --release=$(RELEASE) --center="LRRD Documentation" \
		client/lrrd-client.in > build/doc/lrrd-client.8
	pod2man  --section=8 --release=$(RELEASE) --center="LRRD Documentation" \
		client/lrrd-run.in > build/doc/lrrd-run.8
	pod2man  --section=8 --release=$(RELEASE) --center="LRRD Documentation" \
		client/lrrd-client-configure.in > build/doc/lrrd-client-configure.8
	pod2man  --section=8 --release=$(RELEASE) --center="LRRD Documentation" \
		server/lrrd-graph.in > build/doc/lrrd-graph.8
	pod2man  --section=8 --release=$(RELEASE) --center="LRRD Documentation" \
		server/lrrd-update.in > build/doc/lrrd-update.8
	pod2man  --section=8 --release=$(RELEASE) --center="LRRD Documentation" \
		server/lrrd-html.in > build/doc/lrrd-html.8
	pod2man  --section=8 --release=$(RELEASE) --center="LRRD Documentation" \
		server/lrrd-nagios.in > build/doc/lrrd-nagios.8
	pod2man  --section=8 --release=$(RELEASE) --center="LRRD Documentation" \
		server/lrrd-cron.pod > build/doc/lrrd-cron.8
	pod2man  --section=5 --release=$(RELEASE) --center="LRRD Documentation" \
		server/server.conf.pod > build/doc/server.conf.5
	pod2man  --section=5 --release=$(RELEASE) --center="LRRD Documentation" \
		client/client.conf.pod > build/doc/client.conf.5

	touch build-doc-stamp

deb:
	-rm debian
	-ln -s dists/debian
	fakeroot debian/rules binary

rpm:
	-rm -rf dists/redhat/lrrd-* dists/redhat/noarch
	-dists/redhat/buildtargz.sh
	-rpmbuild \
		--define "_specdir dists/redhat"   \
		--define "_sourcedir dists/redhat" \
		--define "_srcrpmdir dists/redhat" \
                -bs dists/redhat/lrrd.spec

	-rpmbuild \
		--define "_rpmtopdir `pwd`/dists/redhat" \
		--define "_sourcedir %{_rpmtopdir}"      \
		--define "_builddir %{_rpmtopdir}"       \
		--define "_rpmdir %{_rpmtopdir}"         \
	        -bb dists/redhat/lrrd.spec

	-mv dists/redhat/*rpm ..
	-mv dists/redhat/noarch/*rpm ..
	-rm -rf dists/redhat/lrrd-* dists/redhat/noarch

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
	(cd ..; ln -s lrrd lrrd-$(VERSION))
	tar -C .. --dereference --exclude CVS --exclude dists -cvzf ../lrrd_$(RELEASE).tar.gz lrrd-$(VERSION)/

.PHONY: install install-server install-client install-doc build build-doc deb rpm clean source_dist
