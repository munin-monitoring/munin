# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

inherit eutils

MY_P=munin-node-${PV}
S=${WORKDIR}/munin-${PV}

DESCRIPTION="Munin Server Monitoring version ${PV}"

HOMEPAGE="http://munin.sourceforge.net"

SRC_URI="http://heanet.dl.sourceforge.net/sourceforge/munin/munin_${PV}.tar.gz"

LICENSE="GPL-2"

SLOT="0"

KEYWORDS="~x86"

IUSE=""

DEPEND="dev-lang/perl
		app-text/html2text
		dev-perl/net-server
        sys-apps/procps
		app-text/htmldoc"

src_unpack() {
	unpack ${A}
	cd ${S}

	epatch ${FILESDIR}/${PF}-gentoo.patch || die "epatch failed"
}

src_install() {

	enewgroup munin 
	enewuser munin -1 /bin/sh /var/lib/munin munin
	make DESTDIR=${D} install-node || die "install-node failed"
	make DESTDIR=${D} install-node-plugins || die "install-node-plugins failed"
	mkdir -p ${D}/etc/init.d
	fperms 755 ${S}/munin-node
	cp ${S}/munin-node ${D}/etc/init.d/
	cp ${S}/plugins.conf ${D}/etc/munin/plugin-conf.d/munin-node
	fowners munin:munin /var/run/munin
    fowners munin:munin /var/log/munin
    fowners munin:munin /var/lib/munin
}

pkg_postinst() {
	munin-node-configure --shell | sh || die "configure plugins failed"
}
