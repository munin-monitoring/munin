LICENSE=	GPLv2

MUNIN_VERSION=	2.0.49
MUNIN_SITES=	http://downloads.munin-monitoring.org/munin/stable/${MUNIN_VERSION}/
DISTINFO_FILE=	${.CURDIR}/../../sysutils/munin-common/distinfo
PATCHDIR=	${.CURDIR}/../../sysutils/munin-common/files

PORTSCOUT=	limitw:1,even

DBDIR?=		/var/${PORTNAME}
DBDIRNODE?=	/var/${PORTNAME}
LOGDIR?=	/var/log/${PORTNAME}
STATEDIR?=	/var/run/${PORTNAME}
SPOOLDIR?=	/var/spool/${PORTNAME}
MUNIN_DIRS=	BINDIR=${PREFIX}/bin \
		CGIDIR=${PREFIX}/www/cgi-bin \
		CONFDIR=${ETCDIR} \
		DBDIR=${DBDIR} \
		DBDIRNODE=${DBDIRNODE} \
		DOCDIR=${DOCSDIR} \
		HTMLDIR=${WWWDIR} \
		LIBDIR=${DATADIR} \
		LOGDIR=${LOGDIR} \
		MANDIR=${MANPREFIX}/man \
		SBINDIR=${PREFIX}/sbin \
		STATEDIR=${STATEDIR} \
		SPOOLDIR=${SPOOLDIR}
MAKE_ARGS=	${MUNIN_DIRS} \
		BASH=${LOCALBASE}/bin/bash \
		PERL=${PERL} PERLLIB=${PREFIX}/${SITE_PERL_REL}
USERS=		munin
GROUPS=		munin
PLIST_SUB=	${MUNIN_DIRS} USER=${USERS} GROUP=${GROUPS}
SUB_LIST=	${MUNIN_DIRS} USER=${USERS} GROUP=${GROUPS}

CPE_VENDOR=	munin-monitoring

MAKE_JOBS_UNSAFE=	Try to use things before making thems.
