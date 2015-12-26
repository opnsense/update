PROG=	opnsense-verify
MAN=	opnsense-verify.8

SRCS=	config.c pkg.c

CFLAGS+=-I/usr/local/include
LDADD+=	-lelf -lsbuf -lssl -lcrypto
LDADD+=	-L/usr/local/lib -lucl

PREFIX?=${LOCALBASE}
BINDIR=	${PREFIX}/sbin
MANDIR=	${PREFIX}/man/man

.include <bsd.prog.mk>
