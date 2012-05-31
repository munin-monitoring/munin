# New ports collection makefile for:	munin-main
# Date created:				25 Januar 2004
# Whom:					Lupe Christoph <lupe@lupe-christoph.de>
#
# $FreeBSD: ports/sysutils/munin-main/Makefile,v 1.1 2004/03/02 15:52:48 mat Exp $
#

PORTNAME=	munin
PORTVERSION=	1.0.0.p3
CATEGORIES=	sysutils perl5
MASTER_SITES=	${MASTER_SITE_SOURCEFORGE}
MASTER_SITE_SUBDIR=	munin
PKGNAMESUFFIX=	-main
DISTNAME=	munin_1.0.0pre3

MAINTAINER=	lupe@lupe-christoph.de
COMMENT=	Collector part of Munin

BUILD_DEPENDS=	${RUN_DEPENDS}
RUN_DEPENDS=	${SITE_PERL}/${PERL_ARCH}/RRDs.pm:${PORTSDIR}/net/rrdtool \
		${SITE_PERL}/Net/Domain.pm:${PORTSDIR}/net/p5-Net \
		${SITE_PERL}/HTML/Template.pm:${PORTSDIR}/www/p5-HTML-Template

.include <bsd.port.pre.mk>

.if ${PERL_LEVEL} <= 500800
RUN_DEPENDS+=	${SITE_PERL}/${PERL_ARCH}/Storable.pm:${PORTSDIR}/devel/p5-Storable \
		${SITE_PERL}/${PERL_ARCH}/Digest/MD5.pm:${PORTSDIR}/security/p5-Digest-MD5 \
		${SITE_PERL}/${PERL_ARCH}/Time/HiRes.pm:${PORTSDIR}/devel/p5-Time-HiRes
.endif

USE_GMAKE=	yes
PATCH_STRIP=	-p1
WRKSRC=		${WRKDIR}/munin-1.0.0pre3
PKGMESSAGE=	${WRKDIR}/pkg-message
ALL_TARGET=	DATADIR=${DATADIR} build build-man
INSTALL_TARGET=	DATADIR=${DATADIR} install-main

MAN5=		munin.conf.5
MAN8=		munin-cron.8 munin-graph.8 munin-html.8 munin-nagios.8 munin-update.8

pre-install:
	@${SED} 's@%%PREFIX%%@${PREFIX}@g' ${FILESDIR}/pkg-message > ${PKGMESSAGE}
	@PKG_PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} PRE-INSTALL

post-install:
	@${INSTALL_MAN} -d ${PREFIX}/man/man5
	@${INSTALL_MAN} -d ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin.conf.5 ${PREFIX}/man/man5
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-cron.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-graph.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-html.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-nagios.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-update.8 ${PREFIX}/man/man8
	@DATADIR=${DATADIR} PKG_PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} POST-INSTALL
	@${CAT} ${PKGMESSAGE}

.include <bsd.port.post.mk>
