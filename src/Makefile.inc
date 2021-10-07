upgrade: all install clean

VERSIONBIN=		/usr/local/sbin/opnsense-version

.if exists(${VERSIONBIN})
# Latch on to installed base set which is the most likely
# candidate for the current version as the kernel could
# always be a test kernel issued or locked below current
# for driver reasons.
_UPDATE_RELEASE!=	${VERSIONBIN} -v base
.else
_UPDATE_RELEASE=	21.7
.endif

UPDATE_RELEASE?=	${_UPDATE_RELEASE}

_BOOTSTRAP_RELEASE=	${UPDATE_RELEASE:S/./ /g}
BOOTSTRAP_RELEASE?=	${_BOOTSTRAP_RELEASE:[1]}.${_BOOTSTRAP_RELEASE:[2]}
