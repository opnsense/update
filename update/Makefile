SCRIPTS=opnsense-update.sh
MAN=	opnsense-update.8

LOCALBASE?=${DESTDIR}/usr/local
PREFIX?=${LOCALBASE}

BINDIR=	${PREFIX}/sbin
MANDIR=	${PREFIX}/man/man

CLEANFILES=	opnsense-update.sh

opnsense-update.sh: opnsense-update.sh.in
	sed -e 's|%%RELEASE%%|${UPDATE_RELEASE}|g' ${.ALLSRC} > ${.TARGET}

.include <bsd.prog.mk>
