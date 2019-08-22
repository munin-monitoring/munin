# Created by: Sean Rees <sean@rees.us>
# $FreeBSD: head/sysutils/munin-common/Makefile 476509 2018-08-06 12:20:47Z mat $

PORTNAME=	munin
PORTVERSION=	${MUNIN_VERSION}
CATEGORIES=	sysutils perl5
MASTER_SITES=	${MUNIN_SITES}
PKGNAMESUFFIX=	-common

MAINTAINER=	mat@FreeBSD.org
COMMENT=	Common components between a munin node and server

BUILD_DEPENDS=	p5-Module-Build>=0:devel/p5-Module-Build \
		p5-Net-SSLeay>=0:security/p5-Net-SSLeay
RUN_DEPENDS=	p5-Net-SSLeay>=0:security/p5-Net-SSLeay

USES=		gmake perl5 cpe

.include "${.CURDIR}/../munin-common/munin.mk"

ALL_TARGET=	build-common
INSTALL_TARGET=	install-common
NO_ARCH=	yes

post-install:
	${MKDIR} ${STAGEDIR}${LOGDIR} ${STAGEDIR}${STATEDIR} ${STAGEDIR}${SPOOLDIR} ${STAGEDIR}${DBDIR}

.include <bsd.port.mk>
