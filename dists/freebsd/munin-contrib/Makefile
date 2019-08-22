# $FreeBSD: head/sysutils/munin-contrib/Makefile 507372 2019-07-26 20:46:53Z gerald $

PORTNAME=	contrib
DISTVERSION=	git.2019-06-28
PORTREVISION=	1
CATEGORIES=	sysutils
PKGNAMEPREFIX=	munin-

MAINTAINER=	mat@FreeBSD.org
COMMENT=	Contributed plugins and other for munin

LICENSE=	GPLv2

RUN_DEPENDS=	munin-node>=0:sysutils/munin-node

USES=	shebangfix uniquefiles:dirs python:env
SHEBANG_REGEX=	./(${EXAMPLES_DIRS:ts|})/.*
SHEBANG_LANG=	python3 expect gawk zsh
ruby_OLD_CMD=	/opt/csw/bin/ruby
zsh_CMD=	${LOCALBASE}/bin/zsh
python3_CMD=	${LOCALBASE}/bin/python${PYTHON3_DEFAULT}
USE_GITHUB=	yes
GH_ACCOUNT=	munin-monitoring
GH_TAGNAME=	33270dd
GH_TUPLE=	shuque:bind9stats:a920ded:bind9stats

NO_BUILD=	yes
NO_ARCH=	yes

# Most of the installed files are scripts, so give them a "correct" mode.
BINMODE=	755

SUB_FILES=	pkg-message

EXAMPLES_DIRS=	plugins samples templates tools

post-extract:
	@${MV} ${WRKSRC_bind9stats}/bind9stats.py ${WRKSRC}/plugins/bind9stats

do-install:
	@${MKDIR} ${STAGEDIR}${DOCSDIR} ${STAGEDIR}${EXAMPLESDIR}
	${INSTALL_DATA} ${WRKSRC}/README.md ${STAGEDIR}${DOCSDIR}
	cd ${WRKSRC} && ${COPYTREE_BIN} ${EXAMPLES_DIRS:Q} ${STAGEDIR}${EXAMPLESDIR}
	@cd ${STAGEDIR}${PREFIX} && ${FIND} -f * '(' -type f -o -type l ')' >> ${TMPPLIST}

.include <bsd.port.mk>
