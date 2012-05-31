
BASE     = /
VENDOR	 = munin-monitoring.org

PKGNAME  = munin

PREFIX   = $(BASE)/$(PKGNAME)
SUBST    = $(PREFIX)

VERSION	 = $(shell cat ../../RELEASE)
DIST     = ../../../$(PKGNAME)_$(VERSION).tar.gz
#BUILD    = $(PKGNAME)-$(VERSION)
BUILD    = ../../
OSTYPE	 = $(shell uname -p)

PATH    := "/opt/SUNWspro/bin/:/usr/bin:/bin:/usr/local/bin:/usr/ccs/bin/"

DESTDIR := dists/sunos/install/dist/

all: $(PKGNAME)-$(VERSION)-$(OSTYPE).pkg $(PKGNAME)-node-$(VERSION)-$(OSTYPE).pkg

clean: 
	rm -rf pkginfo build-stamp install install-stamp main node configure-stamp
	cd $(BUILD); make clean

#$(BUILD)/configure: $(DIST)
#	gunzip -c $(DIST) | (tar -xf - && touch $(BUILD)/configure)

#configure-stamp: $(BUILD)/configure
#	touch configure-stamp

#build-stamp: $(BUILD)/configure
#	cd $(BUILD) ;\
#	PATH=$(PATH) make build build-doc build-man && touch build-stamp

build-stamp:
	cd $(BUILD) ;\
	PATH=$(PATH) make build build-doc build-man && touch dists/sunos/build-stamp

install-stamp: build-stamp
	mkdir -p install/dist/node install/dist/main
	cd $(BUILD) ;\
	make prefix="" DESTDIR=$(DESTDIR)/node/ CHECKUSER="echo Skipping user check" CHECKGROUP="echo Skipping group check" CHOWN=/bin/true CHGRP=/bin/true install-node install-node-plugins
	-cd $(BUILD) ;\
	make prefix="" DESTDIR=$(DESTDIR)/node CHECKUSER="echo Skipping user check" CHECKGROUP="echo Skipping group check" CHOWN=/bin/true CHGRP=/bin/true  install-doc install-man
	cd $(BUILD) ;\
	make prefix="" DESTDIR=$(DESTDIR)/main CHECKUSER="echo Skipping user check" CHECKGROUP="echo Skipping group check" CHOWN=/bin/true CHGRP=/bin/true install-main
	-cd $(BUILD) ;\
	make prefix="" DESTDIR=$(DESTDIR)/main CHECKUSER="echo Skipping user check" CHECKGROUP="echo Skipping group check" CHOWN=/bin/true CHGRP=/bin/true  install-doc install-man
	touch install-stamp

pkginfo: $(DIST) main/pkginfo node/pkginfo
	echo "Generated pkginfo files."

node/pkginfo: $(DIST)
	-mkdir node
	for f in pkginfo depend compver space request checkinstall \
		preinstall postinstall preremove postremove; do \
		test -r $(PWD)/$$f.node && cp $(PWD)/$$f.node $(PWD)/node/$$f; \
	done ;\
	(echo "# Generated file, do not edit"; \
	echo "PKG=$(PKGNAME)-node"; \
	echo "NAME=$(PKGNAME)-node"; \
	echo "OSTYPE=$(OSTYPE)"; \
	echo "VERSION=$(VERSION)"; \
	echo "CATEGORY=application"; \
	echo "VENDOR=$(VENDOR)"; \
	echo "EMAIL=jimmyo@users.sf.net"; \
	echo "PSTAMP="`getent passwd $(USER) | cut -d: -f5`; \
	echo "BASEDIR=$(BASE)"; \
	echo "CLASSES=none") > $@

main/pkginfo: $(DIST)
	-mkdir main
	for f in pkginfo depend compver space request checkinstall \
		preinstall postinstall preremove postremove; do \
		test -r $(PWD)/$$f.main && cp $(PWD)/$$f.main $(PWD)/main/$$f; \
	done ;\
	(echo "# Generated file, do not edit"; \
	echo "PKG=$(PKGNAME)"; \
	echo "NAME=$(PKGNAME)"; \
	echo "OSTYPE=$(OSTYPE)"; \
	echo "VERSION=$(VERSION)"; \
	echo "CATEGORY=application"; \
	echo "VENDOR=$(VENDOR)"; \
	echo "EMAIL=jimmyo@users.sf.net"; \
	echo "PSTAMP="`getent passwd $(USER) | cut -d: -f5`; \
	echo "BASEDIR=$(BASE)"; \
	echo "CLASSES=none") > $@

install/prototype: install-stamp install/node-prototype install/main-prototype
	echo "Prototypes generated."

install/node-prototype: install-stamp
	for f in pkginfo depend compver space request checkinstall \
		preinstall postinstall preremove postremove; do \
		test -r $(PWD)/node/$$f && echo "i $$f=$(PWD)/node/$$f" || true; done \
		> install/node-prototype
	cd install; pkgproto ../install/dist/node=  \
	| awk ' { $$5="root"; $$6="sys"; } \
		{ print; }' |\
		sed \
		  -e 's|var/opt/munin 0755 root sys|var/opt/munin 0775 root munin|' \
		  -e 's|var/log/munin 0755 root sys|var/log/munin 0775 root munin|' \
		  -e 's|var/run/munin 0755 root sys|var/run/munin 0775 root munin|' \
		>> ../install/node-prototype

install/main-prototype: install-stamp
	for f in pkginfo depend compver space request checkinstall \
		preinstall postinstall preremove postremove; do \
		test -r $(PWD)/main/$$f && echo "i $$f=$(PWD)/main/$$f" || true; done \
		> install/main-prototype
	cd install; pkgproto ../install/dist/main= \
	| awk ' { $$5="root"; $$6="sys"; } \
		{ print; }' |\
		sed \
		  -e 's|var/opt/munin 0755 root sys$$|var/opt/munin 0775 munin munin|' \
		  -e 's|var/log/munin 0755 root sys$$|var/log/munin 0775 munin munin|' \
		  -e 's|var/run/munin 0755 root sys$$|var/run/munin 0775 munin munin|' >> ../install/main-prototype

install/$(PKGNAME): pkginfo install/main-prototype
	cd install; rm prototype || true; ln -s main-prototype prototype; pkgmk -d .

install/$(PKGNAME)-node: pkginfo install/node-prototype
	cd install; rm prototype || true; ln -s node-prototype prototype; pkgmk -d .

$(PKGNAME)-$(VERSION)-$(OSTYPE).pkg: install/$(PKGNAME)
	pkgtrans `pwd`/install $@ $(PKGNAME)
	mv install/$(PKGNAME)-$(VERSION)-$(OSTYPE).pkg .

$(PKGNAME)-node-$(VERSION)-$(OSTYPE).pkg: install/$(PKGNAME)-node
	pkgtrans `pwd`/install $@ $(PKGNAME)-node
	mv install/$(PKGNAME)-node-$(VERSION)-$(OSTYPE).pkg .
