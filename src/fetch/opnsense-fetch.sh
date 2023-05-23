#!/bin/sh

# Copyright (c) 2016-2023 Franco Fichtner <franco@opnsense.org>
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

EXIT=0
OUTFILE=

while getopts ao:qT:w: OPT; do
	case ${OPT} in
	o)
		OUTFILE="${OPTARG}"
		;;
	a|q|T|w)
		;;
	*)
		echo "Usage: man ${0##*/}" >&2
		exit 1
		;;
	esac
done

ERRFILE=$(mktemp -q /tmp/opnsense-fetch.out.XXXXXX)
PIDFILE=$(mktemp -q /tmp/opnsense-fetch.pid.XXXXXX)

# clear the output file for exit code detection
if [ -n "${OUTFILE}" -a -f "${OUTFILE}" ]; then
	rm -f "${OUTFILE}"
fi

daemon -f -m 2 -o ${ERRFILE} -p ${PIDFILE} fetch ${@}

while :; do
	sleep 1
	echo -n .
	[ ! -f ${PIDFILE} ] && break
	pgrep -qF ${PIDFILE} || break
done

# emit a download failure when the file was not written
if [ -n "${OUTFILE}" -a ! -f "${OUTFILE}" ]; then
	echo -n "[$(cat ${ERRFILE})]"
	EXIT=1
fi

rm -f ${ERRFILE} ${PIDFILE}

exit ${EXIT}
