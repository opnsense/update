#!/bin/sh

# Copyright (c) 2016-2024 Franco Fichtner <franco@opnsense.org>
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

# options
DO_FORCE=
DO_NONROOT=
DO_ORIGIN=
DO_REMOVE=
DO_SNAPSHOT=
DO_UPGRADE=
DO_VERBOSE=

# fetch defaults
SITE="https://github.com"
ACCOUNT="opnsense"
DIRECTORY="/usr"

while getopts a:d:fno:rs:uVz OPT; do
	case ${OPT} in
	a)
		ACCOUNT=${OPTARG}
		;;
	d)
		DIRECTORY=${OPTARG}
		;;
	f)
		DO_FORCE="-f"
		;;
	n)
		DO_NONROOT="-n"
		;;
	o)
		DO_ORIGIN="-o ${OPTARG}"
		;;
	r)
		DO_FORCE="-f"
		DO_REMOVE="-r"
		;;
	s)
		SITE=${OPTARG}
		;;
	u)
		DO_UPGRADE="-u"
		;;
	V)
		DO_VERBOSE="-V"
		;;
	z)
		DO_SNAPSHOT="-z"
		;;
	*)
		echo "Usage: man ${0##*/}" >&2
		exit 1
		;;
	esac
done

shift $((OPTIND - 1))

if [ -z "${DO_NONROOT}" -a "$(id -u)" != "0" ]; then
	echo "Must be root." >&2
	exit 1
fi

if [ -n "${DO_VERBOSE}" ]; then
	set -x
fi

if [ ! -f ${GIT} ]; then
	${PKG} install -y git
fi

if [ -z "${*}" -a -z "$(git rev-parse --git-dir 2> /dev/null)" ]; then
	echo "Nothing to do."
	exit 0
fi

ABI=$(opnsense-version -a)
CONF="${DIRECTORY}/tools/config/${ABI}/make.conf"

git_update()
{
	local REPO=${1:-tools}

	if [  -n "${1}" -a -n "${DO_FORCE}" -a -d "${DIRECTORY}/${REPO}" ]; then
		# delete repository contents first...
		for DIR in $(find "${DIRECTORY}/${REPO}" -depth 1); do
			rm -rf "${DIR}"
		done
		# ...as directory may be a mountpoint
		rm -rf "${DIRECTORY}/${REPO}"
	fi

	if [ -n "${1}" -a -n "${DO_REMOVE}" ]; then
		return
	fi

	if [ -d "${DIRECTORY}/${REPO}/.git" ]; then
		(cd "${DIRECTORY}/${REPO}"; git fetch --all --prune; git pull)
	else
		git clone ${SITE}/${ACCOUNT}/${REPO} "${DIRECTORY}/${REPO}"
		BRANCH=
		if [ -f ${CONF} ]; then
			BRANCH=$(make -C /usr/tools -v "$(echo ${REPO} | tr '[:lower:]' '[:upper:]')BRANCH" SETTINGS=${ABI})
		fi
		if [ -z "${DO_SNAPSHOT}" -a -n "${BRANCH}" ]; then
			(cd "${DIRECTORY}/${REPO}"; git checkout ${BRANCH})
		fi
	fi

	if [ -z "${1}" ]; then
		if [ -f "${CONF}" ]; then
			rm -f /etc/make.conf
			make -C /usr/tools make.conf SETTINGS=${ABI} > /etc/make.conf
		elif [ -d "${DIRECTORY}/tools" ]; then
			echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
			echo "!!! ABI ${ABI} is no longer supported !!!" >&2
			echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
		fi
	fi
}

# mandatory tools fetch
git_update

make_upgrade()
{
	TARGETDIR=${1}

	if [ -z "${DO_UPGRADE}" ]; then
		return
	fi

	case "$(basename ${TARGETDIR})" in
	ports)
		if [ -z "${DO_ORIGIN}" ]; then
			echo "Origin (-o) needed for ports upgrade (-u)." >&2
			exit 1
		fi
		# do clean and package creation before doing actual step
		make -C "${TARGETDIR}/${DO_ORIGIN#"-o "}" clean package reinstall
		;;
	plugins)
		if [ -z "${DO_ORIGIN}" ]; then
			echo "Origin (-o) needed for plugins upgrade (-u)." >&2
			exit 1
		fi
		make -C "${TARGETDIR}/${DO_ORIGIN#"-o "}" upgrade
		;;
	*)
		make -C "${TARGETDIR}" upgrade
		;;
	esac
}

for ARG in ${@}; do
	git_update ${ARG}
	make_upgrade "${DIRECTORY}/${ARG}"
done

if [ -z "${*}" ]; then
	# current directory is probably something we need to update
	git fetch --all --prune; git pull
	make_upgrade "$(realpath ${PWD})"
fi
