#!/bin/sh

# Copyright (c) 2016 Franco Fichtner <franco@opnsense.org>
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

# internals
GIT="/usr/local/bin/git"
PKG="/usr/sbin/pkg"
NONROOT=
FORCE=

# fetch defaults
SITE="https://github.com"
ACCOUNT="opnsense"
DIRECTORY="/usr"

while getopts a:d:fns: OPT; do
	case ${OPT} in
	a)
		SCRUB_ARGS=${SCRUB_ARGS};shift;shift
		ACCOUNT=${OPTARG}
		;;
	d)
		SCRUB_ARGS=${SCRUB_ARGS};shift;shift
		ACCOUNT=${OPTARG}
		;;
	f)
		SCRUB_ARGS=${SCRUB_ARGS};shift
		FORCE="-f"
		;;
	n)
		SCRUB_ARGS=${SCRUB_ARGS};shift
		NONROOT="-n"
		;;
	s)
		SCRUB_ARGS=${SCRUB_ARGS};shift;shift
		SITE=${OPTARG}
		;;
	*)
		echo "Usage: opnsense-code repo ..." >&2
		exit 1
		;;
	esac
done

if [ -z "${NONROOT}" -a "$(id -u)" != "0" ]; then
	echo "Must be root."
	exit 1
fi

$(${SCRUB_ARGS})

if [ -z "${*}" ]; then
	echo "Nothing to do."
	exit 0
fi

if [ ! -f ${GIT} ]; then
	${PKG} install -y git
fi

for ARG in ${@}; do
	if [ -n "${FORCE}" ]; then
		rm -rf "${DIRECTORY}/${ARG}"
	fi

	if [ -d "${DIRECTORY}/${ARG}" ]; then
		(cd "${DIRECTORY}/${ARG}"; git pull)
	else
		git clone ${SITE}/${ACCOUNT}/${ARG} "${DIRECTORY}/${ARG}"
	fi

	case ${ARG} in
	tools)
		touch /etc/make.conf
		rm /etc/make.conf
		SETTINGS=$(make -C "${DIRECTORY}/${ARG}" -VSETTINGS)
		ln -s "${DIRECTORY}/${ARG}/config/${SETTINGS}/make.conf" \
		    /etc/make.conf
		;;
	*)
		;;
	esac
done
