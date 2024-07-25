upgrade: all install clean

BINDIR=			${PREFIX}/sbin
MANDIR=			${PREFIX}/share/man/man

VERSIONBIN=		/usr/local/sbin/opnsense-version
FREEBSDBIN=		/bin/freebsd-version

.if exists(${VERSIONBIN})
# Latch on to installed base set which is the most likely
# candidate for the current version as the kernel could
# always be a test kernel issued or locked below current
# for driver reasons.
_UPDATE_RELEASE!=	${VERSIONBIN} -v base
.endif

.if exists(${$FREEBSDBIN})
_UPDATE_FREEBSD!=	${FREEBSDBIN} -u
.endif

UPDATE_RELEASE?=	${_UPDATE_RELEASE}
UPDATE_FREEBSD?=	${_UPDATE_FREEBSD}

_BOOTSTRAP_RELEASE=	${UPDATE_RELEASE:S/./ /g}
BOOTSTRAP_RELEASE?=	${_BOOTSTRAP_RELEASE:[1]}.${_BOOTSTRAP_RELEASE:[2]}

_BOOTSTRAP_FREEBSD=	${UPDATE_FREEBSD:S/-/ /g}
BOOTSTRAP_FREEBSD?=	${_BOOTSTRAP_FREEBSD:[1]}

.if "${BOOTSTRAP_RELEASE}" == "."
.error BOOTSTRAP_RELEASE not set, cannot continue
.endif

.if "${BOOTSTRAP_FREEBSD}" == ""
.error BOOTSTRAP_FREEBSD not set, cannot continue
.endif
