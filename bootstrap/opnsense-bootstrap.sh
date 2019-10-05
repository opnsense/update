#!/bin/sh

# Copyright (c) 2015-2019 Franco Fichtner <franco@opnsense.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

set -e

URL="https://github.com/opnsense/core/archive/stable"
WORKDIR="/tmp/opnsense-bootstrap"
FLAVOUR="OpenSSL"
TYPE="opnsense"
RELEASE="19.7"

DO_BARE=
DO_INSECURE=
DO_FACTORY=
DO_YES=

while getopts bfin:r:t:vy OPT; do
	case ${OPT} in
	b)
		DO_BARE="-b"
		;;
	f)
		DO_FACTORY="-f"
		;;
	i)
		DO_INSECURE="-i"
		;;
	n)
		FLAVOUR=${OPTARG}
		;;
	r)
		RELEASE=${OPTARG}
		;;
	t)
		TYPE=${OPTARG}
		;;
	v)
		echo ${RELEASE}
		exit 0
		;;
	y)
		DO_YES="-y"
		;;
	*)
		echo "Usage: man opnsense-bootstrap" >&2
		exit 1
		;;
	esac
done

shift $((${OPTIND} - 1))

if [ "$(id -u)" != "0" ]; then
	echo "Must be root." >&2
	exit 1
fi

FBSDNAME=$(uname -s)
if [ "${FBSDNAME}" != "FreeBSD" ]; then
	echo "Must be FreeBSD." >&2
	exit 1
fi

FBSDARCH=$(uname -p)
if [ "${FBSDARCH}" != "i386" -a \
    "${FBSDARCH}" != "amd64" ]; then
	echo "Must be i386 or amd64" >&2
	exit 1
fi

FBSDVER=$(uname -r | colrm 4)
if [ "${FBSDVER}" != "11." ]; then
	echo "Must be a FreeBSD 11 release." >&2
	exit 1
fi

echo "This utility will attempt to turn this installation into the latest"
echo "OPNsense ${RELEASE} release.  All packages will be deleted, the base"
echo "system and kernel will be replaced, and if all went well the system"
echo "will automatically reboot."

if [ -z "${DO_YES}" ]; then
	echo
	echo -n "Proceed with this action? [y/N]: "

	read YN
	case ${YN} in
	[yY])
		;;
	*)
		exit 0
		;;
	esac
fi

if [ -n "${DO_FACTORY}" ]; then
	if [ -z "${DO_YES}" ]; then
		echo
		echo -n "Factory reset mode selected, are you sure? [y/N]: "

		read YN
		case ${YN} in
		[yY])
			;;
		*)
			exit 0
			;;
		esac
	fi
fi

if [ -n "${DO_INSECURE}" ]; then
	if [ -z "${DO_YES}" ]; then
		echo
		echo -n "Insecure mode selected, are you sure? [y/N]: "

		read YN
		case ${YN} in
		[yY])
			;;
		*)
			exit 0
			;;
		esac
	fi
fi

echo

rm -rf /usr/local/etc/pkg

rm -rf ${WORKDIR}/*
mkdir -p ${WORKDIR}

export ASSUME_ALWAYS_YES=yes

if [ -n "${DO_INSECURE}" ]; then
	# no CA file around to verify against, user choice
	export SSL_NO_VERIFY_PEER=yes
else
	pkg bootstrap -f
	pkg install ca_root_nss

	# save a copy of the CA file to use for the bootstrap
	cp /etc/ssl/cert.pem ${WORKDIR}/cert.pem
	export SSL_CA_CERT_FILE=${WORKDIR}/cert.pem
fi

fetch -o ${WORKDIR}/core.tar.gz "${URL}/${RELEASE}.tar.gz"
tar -C ${WORKDIR} -xf ${WORKDIR}/core.tar.gz

if [ -z "${DO_BARE}" ]; then
	if pkg -N; then
		pkg unlock -a
		pkg delete -fa
	fi
	rm -f /var/db/pkg/*
fi

make -C ${WORKDIR}/core-stable-${RELEASE} \
    bootstrap DESTDIR= FLAVOUR=${FLAVOUR}

if [ -z "${DO_BARE}" ]; then
	if [ -n "${DO_FACTORY}" ]; then
		rm -rf /conf/*
	fi

	pkg bootstrap
	pkg install ${TYPE}

	# beyond this point verify everything
	unset SSL_NO_VERIFY_PEER
	unset SSL_CA_CERT_FILE

	opnsense-update -bkf
#	reboot
fi
