# New ports collection makefile for:	munin-main
# Date created:				25 January 2004
# Whom:					Lupe Christoph <lupe@lupe-christoph.de>
#
# $FreeBSD: ports/sysutils/munin-main/Makefile,v 1.7 2004/12/14 01:43:10 sem Exp $
#

PORTNAME=	munin
PORTVERSION=	1.2.2
CATEGORIES=	sysutils perl5
MASTER_SITES=	${MASTER_SITE_SOURCEFORGE}
MASTER_SITE_SUBDIR=	munin
PKGNAMESUFFIX=	-main
DISTNAME=	${PORTNAME}_${PORTVERSION:S/.r/rc/}

MAINTAINER=	lupe@lupe-christoph.de
COMMENT=	Collector part of Munin

RUN_DEPENDS=	${SITE_PERL}/${PERL_ARCH}/RRDs.pm:${PORTSDIR}/net/rrdtool \
		${SITE_PERL}/Net/Domain.pm:${PORTSDIR}/net/p5-Net \
		${SITE_PERL}/HTML/Template.pm:${PORTSDIR}/www/p5-HTML-Template \
		${SITE_PERL}/Date/Manip.pm:${PORTSDIR}/devel/p5-Date-Manip
BUILD_DEPENDS=	${RUN_DEPENDS}

.include <bsd.port.pre.mk>

.if ${PERL_LEVEL} <= 500800
RUN_DEPENDS+=	${SITE_PERL}/${PERL_ARCH}/Storable.pm:${PORTSDIR}/devel/p5-Storable \
		${SITE_PERL}/${PERL_ARCH}/Digest/MD5.pm:${PORTSDIR}/security/p5-Digest-MD5 \
		${SITE_PERL}/${PERL_ARCH}/Time/HiRes.pm:${PORTSDIR}/devel/p5-Time-HiRes \
		${SITE_PERL}/Text/Balanced.pm:${PORTSDIR}/textproc/p5-Text-Balanced
.endif

USE_GMAKE=	yes
PATCH_STRIP=	-p1
WRKSRC=		${WRKDIR}/${PORTNAME}-${PORTVERSION:S/.r/rc/}
PKGMESSAGE=	${WRKDIR}/pkg-message
ALL_TARGET=	DATADIR=${DATADIR} PERL=${PERL} build build-man
INSTALL_TARGET=	DATADIR=${DATADIR} PERL=${PERL} install-main

MAN5=		munin.conf.5
MAN8=		munin-cron.8 munin-graph.8 munin-html.8 munin-limits.8 munin-update.8

SUB_FILES=pkg-message

pre-install:
	@PKG_PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} PRE-INSTALL

post-install:
	@${INSTALL_DATA} ${WRKSRC}/build/server/munin.conf ${PREFIX}/etc/munin/munin.conf.sample
	@for man in ${MAN5}; do \
		${INSTALL_MAN} -C ${WRKSRC}/build/doc/$$man ${PREFIX}/man/man5; \
	done
	@for man in ${MAN8}; do \
		${INSTALL_MAN} -C ${WRKSRC}/build/doc/$$man ${PREFIX}/man/man8; \
	done
	@DATADIR=${DATADIR} PKG_PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} POST-INSTALL
	@${CHOWN} munin /var/log/munin-main
	@${CHGRP} munin /var/run/munin /var/log/munin-main ${PREFIX}/www/data/munin ${PREFIX}/var/munin
	@${CAT} ${PKGMESSAGE}

.include <bsd.port.post.mk>
