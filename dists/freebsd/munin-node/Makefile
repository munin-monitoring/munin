# New ports collection makefile for:	munin-node
# Date created:				25 Januar 2004
# Whom:					Lupe Christoph <lupe@lupe-christoph.de>
#
# $FreeBSD: ports/sysutils/munin-node/Makefile,v 1.10 2004/11/16 15:16:37 leeym Exp $
#

PORTNAME=	munin
PORTVERSION=	1.0.4
CATEGORIES=	sysutils perl5
MASTER_SITES=	${MASTER_SITE_SOURCEFORGE}
MASTER_SITE_SUBDIR=	munin
PKGNAMESUFFIX=	-node
DISTNAME=	${PORTNAME}_${PORTVERSION:S/.p/pre/}

MAINTAINER=	lupe@lupe-christoph.de
COMMENT=	Node-specific part of Munin

RUN_DEPENDS=	${SITE_PERL}/Net/Server/Fork.pm:${PORTSDIR}/net/p5-Net-Server
BUILD_DEPENDS=	${RUN_DEPENDS}

.include <bsd.port.pre.mk>

.if ${PERL_LEVEL} < 500800
RUN_DEPENDS+=	${SITE_PERL}/Net/Domain.pm:${PORTSDIR}/net/p5-Net
.endif

USE_GMAKE=	yes
PATCH_STRIP=	-p1
WRKSRC=		${WRKDIR}/${PORTNAME}-${PORTVERSION:S/.p/pre/}
PKGMESSAGE=	${WRKDIR}/pkg-message
ALL_TARGET=	DATADIR=${DATADIR} build build-man
INSTALL_TARGET=	DATADIR=${DATADIR} install-node install-node-plugins
MAKE_ENV=	LANG=C
NOPRECIOUSMAKEVARS=yes

MAN5=		munin-node.conf.5
MAN8=		munin-node-configure.8 munin-node.8 munin-run.8

.if ${OSVERSION} < 500000
PKGMSG=${FILESDIR}/pkg-message.4
STARTSTOP_SRC=${FILESDIR}/munin-node.sh
STARTSTOP_DST=${PREFIX}/etc/rc.d/munin-node.sh
.else
PKGMSG=${FILESDIR}/pkg-message
STARTSTOP_SRC=${FILESDIR}/munin_node.sh
STARTSTOP_DST=/etc/rc.d/munin_node
.endif

pre-install:
	@${SED} 's@%%PREFIX%%@${PREFIX}@g' ${PKGMSG} > ${PKGMESSAGE}
	@PKG_PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} PRE-INSTALL

post-install:
	@${SED} 's@%PREFIX%@${LOCALBASE}@g' ${STARTSTOP_SRC} > ${STARTSTOP_DST}
	@${CHMOD} +x ${STARTSTOP_DST}
	${INSTALL_DATA} ${WRKSRC}/build/node/munin-node.conf ${PREFIX}/etc/munin/munin-node.conf.sample
	${INSTALL_DATA} ${WRKSRC}/plugins.conf ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf.sample
	@if [ ! -f ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf ]; then \
		${INSTALL_DATA} ${WRKSRC}/plugins.conf ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf; \
	fi
	@${CAT} ${PKGMESSAGE}
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node.conf.5 ${PREFIX}/man/man5
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node-configure.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-run.8 ${PREFIX}/man/man8
	@PKG_PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} POST-INSTALL
	@${ECHO} ${DISTNAME} | ${SED} -e 's/munin_//' > ${PREFIX}/etc/munin/VERSION.node

.include <bsd.port.post.mk>
