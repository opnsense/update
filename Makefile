SCRIPTS=opnsense-update.sh opnsense-bootstrap.sh
MAN=	opnsense-update.8 opnsense-bootstrap.8

PREFIX?=${LOCALBASE}
BINDIR=	${PREFIX}/sbin
MANDIR=	${PREFIX}/man/man

.include <bsd.prog.mk>
