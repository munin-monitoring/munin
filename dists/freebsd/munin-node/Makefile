# New ports collection makefile for:	munin-node
# Date created:				25 Januar 2004
# Whom:					Lupe Christoph <lupe@lupe-christoph.de>
#
# $FreeBSD$
#
# $Log$
# Revision 1.2  2004/02/01 18:13:50  lupe
# Update to munin_1.0.0pre2. Added call to new pkg-install and VERSION marker.
#
#

PORTNAME=	munin
PORTVERSION=	1.0.0.p2
CATEGORIES=	sysutils perl5
MASTER_SITES=	${MASTER_SITE_SOURCEFORGE}
MASTER_SITE_SUBDIR=	munin
PKGNAMESUFFIX=	-node
DISTNAME=	munin_1.0.0pre2

MAINTAINER=	lupe@lupe-christoph.de
COMMENT=	Node-specific part of Munin

.include <bsd.port.pre.mk>

#RUN_DEPENDS=	${SITE_PERL}/Net/Server/Fork.pm:${PORTSDIR}/net/p5-Net-Server \
#		${SITE_PERL}/Config/General.pm:${PORTSDIR}/devel/p5-Config-General
RUN_DEPENDS=	${SITE_PERL}/Net/Server/Fork.pm:${PORTSDIR}/net/p5-Net-Server
.if ${PERL_LEVEL} < 500800
RUN_DEPENDS+=	${SITE_PERL}/Net/Domain.pm:${PORTSDIR}/net/p5-Net
.endif
BUILD_DEPENDS=	${RUN_DEPENDS}

USE_GMAKE=	yes
PATCH_STRIP=	-p1
WRKSRC=		${WRKDIR}/munin-1.0.0pre2
ALL_TARGET=	build build-man
INSTALL_TARGET=	install-node install-node-plugins

MAN5=		munin-node.conf.5
MAN8=		munin-node-configure.8 munin-node.8 munin-run.8

pre-install:
	@${SED} 's@\$$(PREFIX)@${LOCALBASE}@g' ${FILESDIR}/pkg-message > ${PKGMESSAGE}
	@PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} PRE-INSTALL

post-install:
	@${SED} 's@%PREFIX%@${LOCALBASE}@g' ${FILESDIR}/munin-node.sh > ${PREFIX}/etc/rc.d/munin-node.sh
	@${CHMOD} +x ${PREFIX}/etc/rc.d/munin-node.sh
	@if [ ! -f ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf ]; then \
		${INSTALL_DATA} ${WRKSRC}/plugins.conf ${PREFIX}/etc/munin/plugin-conf.d/plugins.conf; \
	fi
	@${CAT} ${PKGMESSAGE}
	@${INSTALL_MAN} -d ${PREFIX}/man/man5
	@${INSTALL_MAN} -d ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node.conf.5 ${PREFIX}/man/man5
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node-configure.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-node.8 ${PREFIX}/man/man8
	@${INSTALL_MAN} -C ${WRKSRC}/build/doc/munin-run.8 ${PREFIX}/man/man8
	@PREFIX=${PREFIX} ${SH} pkg-install ${PKGNAME} POST-INSTALL
	@echo ${munin_1.0.0pre2} | sed -e 's/munin_//' > ${PREFIX}/etc/munin/VERSION.node

.include <bsd.port.post.mk>
