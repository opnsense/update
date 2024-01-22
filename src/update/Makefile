SCRIPTS=opnsense-update.sh
MAN=	opnsense-update.8

LOCALBASE?=${DESTDIR}/usr/local
PREFIX?=${LOCALBASE}

CLEANFILES=	${SCRIPTS}

${SCRIPTS}: ${SCRIPTS}.in
	sed -e 's|%%RELEASE%%|${UPDATE_RELEASE}|g' ${.ALLSRC} > ${.TARGET}

.include <bsd.prog.mk>
