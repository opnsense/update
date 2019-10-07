#!/bin/sh

# Copyright (c) 2016-2019 Franco Fichtner <franco@opnsense.org>
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

if [ "$(id -u)" != "0" ]; then
	echo "Must be root."
	exit 1
fi

WORKPREFIX="/tmp/opnsense-revert"
OPENSSL="/usr/local/bin/openssl"
WORKDIR=${WORKPREFIX}/${$}
PKG="pkg-static"

INSECURE=
LOCKSTRIP=1
RELEASE=

while getopts ir: OPT; do
	case ${OPT} in
	i)
		INSECURE="insecure"
		;;
	l)
		LOCKSTRIP=
		;;
	r)
		RELEASE="${OPTARG}"
		;;
	*)
		echo "Usage: man ${0##*/}" >&2
		exit 1
		;;
	esac
done

shift $((${OPTIND} - 1))

for PACKAGE in ${@}; do
	if ! ${PKG} query %n ${PACKAGE} > /dev/null; then
		echo "Package '${PACKAGE}' is not installed" >&2
		exit 1
	fi
done

export ASSUME_ALWAYS_YES=yes

FLAVOUR="Base"
if [ -f ${OPENSSL} ]; then
	FLAVOUR=$(${OPENSSL} version | awk '{ print $1 }')
fi

MIRROR="$(opnsense-update -M)/MINT/${RELEASE}/${FLAVOUR}/Latest"
COREPKG=$(opnsense-version -n 2> /dev/null || true)
COREDEP=

if [ -n "${COREPKG}" ]; then
	COREDEP=$(echo ${COREPKG}; ${PKG} query %dn ${COREPKG})
fi

fetch()
{
	STAGE1="opnsense-fetch -a -T 30 -q -o ${WORKDIR}/${1}.sig ${MIRROR}/${1}.sig"
	STAGE2="opnsense-fetch -a -T 30 -q -o ${WORKDIR}/${1} ${MIRROR}/${1}"
	STAGE3="opnsense-verify ${WORKDIR}/${1}"

	if [ -n "${INSECURE}" ]; then
		# no signature, no cry
		STAGE1=":"
		STAGE3=":"
	fi

	echo -n "Fetching ${1}: ."

	mkdir -p ${WORKDIR} && ${STAGE1} && ${STAGE2} && \
	    echo " done" && ${STAGE3} && return

	echo " failed"
	exit 1
}

for PACKAGE in ${@}; do
	if [ -z "${RELEASE}" ]; then
		${PKG} fetch ${PACKAGE}
	else
		fetch ${PACKAGE}.txz
	fi
done

for PACKAGE in ${@}; do
	# reset automatic, vital as per package metadata
	AUTOMATIC="-A"

	if [ -n "${COREPKG}" -a "$(echo "${COREDEP}" | grep -c ${PACKAGE})" != "0" ]; then
		if [ "${COREPKG}" = ${PACKAGE} ]; then
			AUTOMATIC=
		fi
	elif [ "$(${PKG} query %a ${PACKAGE})" = "0" ]; then
		AUTOMATIC=
	fi

	if [ -n "${LOCKSTRIP}" ]; then
		# ignore active locks and do not let them persist
		${PKG} unlock ${PACKAGE}
	fi

	if [ -z "${RELEASE}" ]; then
		${PKG} install -f ${AUTOMATIC} ${PACKAGE}
	else
		${PKG} install -f ${AUTOMATIC} ${WORKDIR}/${PACKAGE}.txz
	fi
done

rm -rf ${WORKPREFIX}/*
