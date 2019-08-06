# New ports collection makefile for:	munin-node
# Date created:				25 January 2004
# Whom:					Lupe Christoph <lupe@lupe-christoph.de>
#
# $FreeBSD: ports/sysutils/munin-node/Makefile,v 1.12 2004/12/14 01:43:10 sem Exp $
#

PORTNAME=	munin
PORTVERSION=	1.2.2
CATEGORIES=	sysutils perl5
MASTER_SITES=	${MASTER_SITE_SOURCEFORGE}
MASTER_SITE_SUBDIR=	munin
PKGNAMESUFFIX=	-node
DISTNAME=	${PORTNAME}_${PORTVERSION:S/.r/rc/}

MAINTAINER=	lupe@lupe-christoph.de
COMMENT=	Node-specific part of Munin

RUN_DEPENDS=	${SITE_PERL}/Net/Server/Fork.pm:${PORTSDIR}/net/p5-Net-Server
BUILD_DEPENDS=	${RUN_DEPENDS}

.include <bsd.port.pre.mk>

.if ${OSVERSION} < 500000
RUN_DEPENDS=	${LOCALBASE}/etc/rc.subr:${PORTSDIR}/sysutils/rc_subr
.endif

.if ${PERL_LEVEL} < 500800
RUN_DEPENDS+=	${SITE_PERL}/Net/Domain.pm:${PORTSDIR}/net/p5-Net
.endif

USE_GMAKE=	yes
PATCH_STRIP=	-p1
WRKSRC=		${WRKDIR}/${PORTNAME}-${PORTVERSION:S/.r/rc/}
PKGMESSAGE=	${WRKDIR}/pkg-message
ALL_TARGET=	DATADIR=${DATADIR} PERL=${PERL} build build-man
INSTALL_TARGET=	DATADIR=${DATADIR} PERL=${PERL} INSTALL_PLUGINS="auto manual snmpauto" install-node install-node-plugins
MAKE_ENV=	LANG=C

MAN5=		munin-node.conf.5
MAN8=		munin-node-configure.8 munin-node.8 munin-run.8

SUB_FILES=	pkg-message munin-node.sh munin-node-revive.sh
SUB_LIST=	RC_SUBR=${RC_SUBR}
USE_RC_SUBR=	YES

pre-install:
	@PKG_PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} PRE-INSTALL

post-install:
	${INSTALL_SCRIPT} ${WRKDIR}/munin-node.sh ${PREFIX}/etc/rc.d/munin-node.sh
.if ${PERL_LEVEL} < 500800
	${INSTALL_SCRIPT} ${WRKDIR}/munin-node-revive.sh ${PREFIX}/bin/munin-node-revive
.endif
	${INSTALL_DATA} ${WRKSRC}/build/node/munin-node.conf ${PREFIX}/etc/munin/munin-node.conf.sample
	${INSTALL_DATA} files/plugins.conf ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf.sample
	@if [ ! -f ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf ]; then \
		${INSTALL_DATA} ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf.sample ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf; \
	fi
	@${CAT} ${PKGMESSAGE}
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node.conf.5 ${PREFIX}/man/man5
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node-configure.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-run.8 ${PREFIX}/man/man8
	@PKG_PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} POST-INSTALL
	@${ECHO} ${DISTNAME} | ${SED} -e 's/munin_//' > ${PREFIX}/etc/munin/VERSION.node

.include <bsd.port.post.mk>
