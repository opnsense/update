#!/bin/sh

# Copyright (c) 2016-2017 Franco Fichtner <franco@opnsense.org>
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

# internal vars
WORKDIR="/tmp/opnsense-patch"
PREFIX="/usr/local"
INSECURE=

# fetch defaults
SITE="https://github.com"
ACCOUNT="opnsense"
REPOSITORY="core"
PATCHLEVEL="2"

if [ "$(id -u)" != "0" ]; then
	echo "Must be root."
	exit 1
fi

while getopts a:c:ip:r:s: OPT; do
	case ${OPT} in
	a)
		ACCOUNT=${OPTARG}
		;;
	c)
		case ${OPTARG} in
		core)
			REPOSITORY="core"
			PATCHLEVEL="2"
			;;
		plugins)
			REPOSITORY="plugins"
			PATCHLEVEL="4"
			;;
		*)
			echo "Unknown repository default: ${OPTARG}" >&2
			exit 1
			;;
		esac
		;;
	i)
		INSECURE="--no-verify-peer"
		;;
	p)
		PATCHLEVEL=${OPTARG}
		;;
	r)
		REPOSITORY=${OPTARG}
		;;
	s)
		SITE=${OPTARG}
		;;
	*)
		echo "Usage: opnsense-patch [-c repo_default] commit_hash ..." >&2
		exit 1
		;;
	esac
done

shift $((${OPTIND} - 1))

mkdir -p ${WORKDIR}

for ARG in ${@}; do
	fetch ${INSECURE} -q \
	    "${SITE}/${ACCOUNT}/${REPOSITORY}/commit/${ARG}.patch" \
	    -o "${WORKDIR}/${ARG}.patch"
done

for ARG in ${@}; do
	patch -Et -p ${PATCHLEVEL} -d "${PREFIX}" -i "${WORKDIR}/${ARG}.patch"
	cat "${WORKDIR}/${ARG}.patch" | while read PATCHLINE; do
		case "${PATCHLINE}" in
		"diff --git "*" b/src/"*)
			PATCHFILE="${PREFIX}/$(echo "${PATCHLINE}" | awk '{print $4 }' | cut -c 7-)"
			;;
		"new file mode "*)
			PATCHMODE=$(echo "${PATCHLINE}" | awk '{print $4 }' | cut -c 4-6)
			if [ "${PATCHMODE}" = "644" -o "${PATCHMODE}" = "755" ]; then
				if [ -f "${PATCHFILE}" ]; then
					chmod ${PATCHMODE} "${PATCHFILE}"
				fi
			fi
			;;
		"index "*|"new mode "*)
			# we can't figure out if we are new or old, thus no "old mode " handling
			PATCHMODE=$(echo "${PATCHLINE}" | awk '{print $3 }' | cut -c 4-6)
			if [ "${PATCHMODE}" = "644" -o "${PATCHMODE}" = "755" ]; then
				if [ -f "${PATCHFILE}" ]; then
					chmod ${PATCHMODE} "${PATCHFILE}"
				fi
			fi
			;;
		esac
	done
done

rm -rf ${WORKDIR}/*

echo "All patches have been applied successfully.  Have a nice day."
