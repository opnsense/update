#!/bin/sh

# Copyright (c) 2015 Franco Fichtner <franco@opnsense.org>
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

PREFIX=
CERT=
KEY=

while getopts c:k:p: OPT; do
	case ${OPT} in
	c)
		CERT=${OPTARG}
		;;
	k)
		KEY=${OPTARG}
		;;
	p)
		PREFIX=${OPTARG}
		;;
	*)
		echo "Usage: opnsense-sign -p prefix file" >&2
		exit 1
		;;
	esac
done

shift $((${OPTIND} - 1))

FILE=${1}

if [ -n "${PREFIX}" ]; then
	CERT=${PREFIX}.pub
	KEY=${PREFIX}.key
fi

if [ ! -r "${KEY}" ]; then
	echo "Cannot find private key: ${KEY}" >&2
	exit 1
fi

if [ ! -r "${CERT}" ]; then
	echo "Cannot find public certificate: ${CERT}" >&2
	exit 1
fi

if [ ! -r "${FILE}" ]; then
	echo "Cannot find file: ${FILE}" >&2
	exit 1
fi

SUM=$(sha256 -q ${FILE})
if [ -z "${SUM}" ]; then
	echo "Error fetching checksum" >&2
	exit 1
fi

(
	echo SIGNATURE
	echo -n ${SUM} | openssl dgst -sign ${KEY} -sha256 -binary
	echo
	echo CERT
	cat ${CERT}
	echo END
) > ${FILE}.sig

exit 0
