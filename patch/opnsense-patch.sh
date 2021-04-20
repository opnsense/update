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

# internal vars
ARGS=
CACHEDIR="/var/cache/opnsense-patch"
PATCHES=
PREFIX="/usr/local"
REFRESH="/usr/local/opnsense/www/index.php"

# fetch defaults
SITE="https://github.com"
ACCOUNT="opnsense"
REPOSITORY="core"
PATCHLEVEL="2"

# user options
DO_FORCE=
DO_FORWARD="-t"
DO_DOWNLOAD=
DO_INSECURE=
DO_LIST=

if [ "$(id -u)" != "0" ]; then
	echo "Must be root." >&2
	exit 1
fi

while getopts a:c:defilNp:r:s: OPT; do
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
	d)
		DO_DOWNLOAD="-d"
		;;
	e)
		rm -rf ${CACHEDIR}/*
		;;
	f)
		DO_FORCE="-f"
		;;
	i)
		DO_INSECURE="--no-verify-peer"
		;;
	l)
		DO_LIST="-l"
		;;
	N)
		DO_FORWARD="-f"
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
		echo "Usage: man ${0##*/}" >&2
		exit 1
		;;
	esac
done

shift $((${OPTIND} - 1))

if [ ${PATCHLEVEL} -lt 2 ]; then
	echo "Patch level must be >= 2." >&2
	exit 1
fi

mkdir -p ${CACHEDIR}

patch_load()
{
	for PATCH in $(find ${CACHEDIR}/ -name "${REPOSITORY}-*"); do
		if [ ! -s "${PATCH}" ]; then
			rm -f "${PATCH}"
			continue
		fi

		HASH=$(grep '^From [0-9a-f]' ${PATCH} | cut -d ' ' -f 2)
		SUBJECT=$(grep '^Subject: \[PATCH\]' ${PATCH} | cut -d ' ' -f 3-)
		FILE=$(basename ${PATCH})

		if [ -z "${HASH}" -o -z "${SUBJECT}" ]; then
			rm -f "${PATCH}"
			continue
		fi

		echo ${FILE} ${HASH} ${SUBJECT}
	done
}

PATCHES=$(patch_load)

patch_found()
{
	ARG=${1}
	ARGLEN=$(echo -n ${ARG} | wc -c | awk '{ print $1 }')

	echo "${PATCHES}" | while read FILE HASH SUBJECT; do
		if [ "$(echo ${HASH} | cut -c -${ARGLEN})" = ${ARG} ]; then
			echo ${FILE}
			return
		fi
	done
}

patch_print()
{
	echo "${PATCHES}" | while read FILE HASH SUBJECT; do
		if [ -z "${FILE}" ]; then
			continue
		fi
		LINE="$(echo ${HASH} | cut -c -11)"
		LINE="${LINE} $(echo ${SUBJECT} | cut -c -50)"
		echo ${LINE}
	done
}

if [ -n "${DO_LIST}" ]; then
	patch_print
	exit 0
fi

for ARG in ${@}; do
	FOUND="$(patch_found ${ARG})"

	if [ -n "${FOUND}" ]; then
		if [ -n "${DO_FORCE}" ]; then
			rm ${CACHEDIR}/${FOUND}
		else
			echo "Found local copy of ${ARG}, skipping fetch."
			ARGS="${ARGS} ${FOUND}"
			continue
		fi
	fi

	WANT="${REPOSITORY}-${ARG}"

	fetch ${DO_INSECURE} -q -o "${CACHEDIR}/~${WANT}" \
	    "${SITE}/${ACCOUNT}/${REPOSITORY}/commit/${ARG}.patch"

	if [ ! -s "${CACHEDIR}/~${WANT}" ]; then
		rm -f "${CACHEDIR}/~${WANT}"
		echo "Failed to fetch: ${ARG}" >&2
		exit 1
	fi

	DISCARD=

	while IFS= read -r PATCHLINE; do
		case "${PATCHLINE}" in
		"diff --git a/"*" b/"*)
			PATCHFILE="$(echo "${PATCHLINE}" | awk '{print $4 }')"
			for INDEX in $(seq 2 ${PATCHLEVEL}); do
				PATCHFILE=${PATCHFILE#*/}
			done
			if [ -n "${PATCHFILE##src/*}" ]; then
				DISCARD=1
			else
				DISCARD=
			fi
			;;
		esac

		if [ -n "${DISCARD}" ]; then
			continue
		fi

		echo "${PATCHLINE}" >> "${CACHEDIR}/${WANT}"
	done < "${CACHEDIR}/~${WANT}"

	echo "Fetched ${ARG} via ${SITE}/${ACCOUNT}/${REPOSITORY}"

	ARGS="${ARGS} ${WANT}"
done

rm -f ${CACHEDIR}/~*

if [ -n "${DO_DOWNLOAD}" ]; then
	ARGS=
fi

for ARG in ${ARGS}; do
	# XXX from here we could figure out if we will run in reverse...
	if ! patch ${DO_FORWARD} -sCE -p ${PATCHLEVEL} -d "${PREFIX}" -i "${CACHEDIR}/${ARG}"; then
		exit 1
	fi

	patch ${DO_FORWARD} -E -p ${PATCHLEVEL} -d "${PREFIX}" -i "${CACHEDIR}/${ARG}"

	while IFS= read -r PATCHLINE; do
		case "${PATCHLINE}" in
		"diff --git a/"*" b/"*)
			PATCHFILE="$(echo "${PATCHLINE}" | awk '{print $4 }')"
			for INDEX in $(seq 1 ${PATCHLEVEL}); do
				PATCHFILE=${PATCHFILE#*/}
			done
			PATCHFILE="${PREFIX}/${PATCHFILE}"
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
	done < "${CACHEDIR}/${ARG}"
done

if [ -n "${ARGS}" ]; then
	echo "All patches have been applied successfully.  Have a nice day."
fi

if [ -f ${REFRESH} ]; then
	# always force browser to reload JS/CSS
	touch ${REFRESH}
fi

rm -f /tmp/opnsense_menu_cache.xml
