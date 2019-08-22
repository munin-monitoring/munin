# Created by: Lupe Christoph <lupe@lupe-christoph.de>
# $FreeBSD: head/sysutils/munin-master/Makefile 494589 2019-03-04 12:17:39Z mat $

PORTNAME=	munin
PORTVERSION=	${MUNIN_VERSION}
CATEGORIES=	sysutils perl5
MASTER_SITES=	${MUNIN_SITES}
PKGNAMESUFFIX=	-master

MAINTAINER=	mat@FreeBSD.org
COMMENT=	Collector part of Munin

BUILD_DEPENDS=	p5-Module-Build>=0:devel/p5-Module-Build \
		munin-common>=${MUNIN_VERSION}:sysutils/munin-common \
		rrdtool>=0:databases/rrdtool \
		p5-CGI>=0:www/p5-CGI \
		p5-DateTime-HiRes>=0:devel/p5-DateTime-HiRes \
		p5-File-Copy-Recursive>=0:devel/p5-File-Copy-Recursive \
		p5-HTML-Template>=0:www/p5-HTML-Template \
		p5-IO-Socket-INET6>=0:net/p5-IO-Socket-INET6 \
		p5-Log-Log4perl>=0:devel/p5-Log-Log4perl \
		p5-Net-SSLeay>=0:security/p5-Net-SSLeay \
		p5-Params-Validate>=0:devel/p5-Params-Validate
RUN_DEPENDS=	munin-common>=${MUNIN_VERSION}:sysutils/munin-common \
		rrdtool>=0:databases/rrdtool \
		p5-CGI>=0:www/p5-CGI \
		p5-CGI-Fast>=0:www/p5-CGI-Fast \
		p5-DateTime-HiRes>=0:devel/p5-DateTime-HiRes \
		p5-File-Copy-Recursive>=0:devel/p5-File-Copy-Recursive \
		p5-HTML-Template>=0:www/p5-HTML-Template \
		p5-IO-Socket-INET6>=0:net/p5-IO-Socket-INET6 \
		p5-Log-Log4perl>=0:devel/p5-Log-Log4perl \
		p5-Net-SSLeay>=0:security/p5-Net-SSLeay \
		p5-Params-Validate>=0:devel/p5-Params-Validate \
		p5-URI>=0:net/p5-URI \
		p5-Date-Manip>=0:devel/p5-Date-Manip \
		p5-FCGI>=0:www/p5-FCGI

USES=		gmake perl5 cpe

.include "${.CURDIR}/../munin-common/munin.mk"

ALL_TARGET=	infiles build-master build-man
INSTALL_TARGET=	install-master-prime
NO_ARCH=	yes

SUB_FILES=	pkg-message
PLIST_SUB+=	WWWOWN=${WWWOWN} WWWGRP=${WWWGRP}

PORTSCOUT=	ignore:1

post-install:
	(cd ${WRKSRC}/build/doc; \
		${INSTALL_MAN} munin.conf.5 ${STAGEDIR}${MAN5PREFIX}/man/man5; \
		${INSTALL_MAN} munin-cron.8 munin-graph.8 munin-html.8 munin-limits.8 munin-update.8 ${STAGEDIR}${MAN8PREFIX}/man/man8; \
	)
	(cd ${STAGEDIR}${ETCDIR}; for i in `find . -type f`; do mv $$i $$i.sample; done)
	${MV} ${STAGEDIR}${WWWDIR}/.htaccess ${STAGEDIR}${WWWDIR}/.htaccess.sample
	${INSTALL_DATA} ${FILESDIR}/newsyslog ${STAGEDIR}${ETCDIR}/munin-master.newsyslog

.include <bsd.port.mk>
