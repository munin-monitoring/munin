# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

inherit eutils

MY_P=munin-${PV}
S=${WORKDIR}/${MY_P}

DESCRIPTION="Munin Server Monitoring version ${PV}"

HOMEPAGE="http://munin.sourceforge.net"

SRC_URI="http://heanet.dl.sourceforge.net/sourceforge/munin/${PN}_${PV}.tar.gz"

LICENSE="GPL-2"

SLOT="0"

KEYWORDS="~x86"

IUSE=""

DEPEND="dev-lang/perl
		net-analyzer/rrdtool
		app-text/html2text
		dev-perl/HTML-Template
		dev-perl/net-server
		dev-perl/Getopt-Long
		dev-perl/Storable
		sys-apps/procps
		app-text/htmldoc"

src_unpack() {
	unpack ${A}
	cd ${S}

	epatch ${FILESDIR}/${PF}-gentoo.patch || die "epatch failed"
}

src_compile() {
	make build || die "compile failed (make build)"
}

src_install() {
    enewgroup munin
    enewuser munin -1 /bin/sh /var/lib/munin munin
    fowners munin:munin /var/log/munin
    fowners munin:munin /var/lib/munin

	make DESTDIR=${D} install || die "install failed"
}

pkg_postinst() {
	einfo ""
	einfo "IMPORTANT!!!"
	einfo ""
	einfo "You will need to add the cron jobs to execute munin-cron every 5 minutes as user munin."
	einfo "One way of doing this is as follows:"
	einfo ""
	einfo "crontab -u munin -e"
	einfo ""
	einfo "Then add the following lines, save, exit and restart your cron program:"
	einfo ""
	einfo "*/5 * * * *     if [ -x /usr/bin/munin-cron ]; then /usr/bin/munin-cron; fi"
	einfo "10 10 * * *     if [ -x /usr/share/munin/munin-nagios ]; then /usr/share/munin/munin-nagios --removeok; fi"
	einfo ""
}
