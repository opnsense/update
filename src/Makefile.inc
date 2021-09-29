upgrade: all install clean

VERSIONBIN=		/usr/local/sbin/opnsense-version

.if exists(${VERSIONBIN})
_UPDATE_RELEASE!=	${VERSIONBIN} -v base
.else
_UPDATE_RELEASE=	21.7
.endif

UPDATE_RELEASE?=	${_UPDATE_RELEASE}

_BOOTSTRAP_RELEASE=	${UPDATE_RELEASE:S/./ /g}
BOOTSTRAP_RELEASE?=	${_BOOTSTRAP_RELEASE:[1]}.${_BOOTSTRAP_RELEASE:[2]}
