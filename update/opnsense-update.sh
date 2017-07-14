#!/bin/sh

# Copyright (c) 2015-2017 Franco Fichtner <franco@opnsense.org>
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

SIG_KEY="^[[:space:]]*signature_type:[[:space:]]*"
URL_KEY="^[[:space:]]*url:[[:space:]]*"

ORIGIN="/usr/local/etc/pkg/repos/origin.conf"
VERSIONDIR="/usr/local/opnsense/version"
WORKPREFIX="/var/cache/opnsense-update"
PENDINGDIR="${WORKPREFIX}/.sets.pending"
OPENSSL="/usr/local/bin/openssl"
WORKDIR=${WORKPREFIX}/${$}
KERNELDIR="/boot/kernel"
PKG="pkg-static"
ARCH=$(uname -p)
VERSION="17.1.9"

if [ ! -f ${ORIGIN} ]; then
	echo "Missing origin.conf"
	exit 1
fi

INSTALLED_BASE=
if [ -f ${VERSIONDIR}/base ]; then
	INSTALLED_BASE=$(cat ${VERSIONDIR}/base)
fi

INSTALLED_KERNEL=
if [ -f ${VERSIONDIR}/kernel ]; then
	INSTALLED_KERNEL=$(cat ${VERSIONDIR}/kernel)
fi

kernel_version() {
	# It's faster to ask uname as long as the base
	# system is consistent that should work instead
	# of doing the magic of `freebsd-version -k'.
	uname -r
}

base_version() {
	# The utility has the version embedded, so
	# we execute it to check which one it is.
	FREEBSD_VERSION="${1}/bin/freebsd-version"
	if [ -f "${FREEBSD_VERSION}" ]; then
		${FREEBSD_VERSION}
	fi
}

mirror_abi()
{
	# The first part after ABI is our suffix and
	# we need all of it to find the correct sets.
	MIRROR=$(sed -n 's/'"${URL_KEY}"'\"pkg\+\(.*\/${ABI}\/[^\/]*\)\/.*/\1/p' ${ORIGIN})
	ABI=$(opnsense-verify -a 2> /dev/null)
	if [ -n "${DO_ABI}" ]; then
		ABI=${DO_ABI#"-a "}
	fi
	eval MIRROR="${MIRROR}"
	echo "${MIRROR}"
}

empty_cache() {
	if [ -d ${WORKPREFIX} ]; then
		# completely empty cache as per request
		rm -rf ${WORKPREFIX}/* ${WORKPREFIX}/.??*
	fi
}

DO_MIRRORDIR=
DO_MIRRORURL=
DO_DEFAULTS=
DO_INSECURE=
DO_RELEASE=
DO_FLAVOUR=
DO_UPGRADE=
DO_VERSION=
DO_KERNEL=
DO_LOCAL=
DO_FORCE=
DO_CHECK=
DO_HIDE=
DO_BASE=
DO_PKGS=
DO_SKIP=
DO_TYPE=
DO_ABI=

while getopts a:Bbcdefhikl:Mm:N:n:Ppr:st:uv OPT; do
	case ${OPT} in
	a)
		DO_ABI="-a ${OPTARG}"
		;;
	B)
		DO_FORCE="-f"
		DO_BASE="-B"
		DO_KERNEL=
		DO_PKGS=
		;;
	b)
		DO_BASE="-b"
		;;
	c)
		DO_CHECK="-c"
		;;
	d)
		DO_DEFAULTS="-d"
		;;
	e)
		empty_cache
		;;
	f)
		DO_FORCE="-f"
		;;
	h)
		DO_HIDE="-h"
		;;
	i)
		DO_INSECURE="-i"
		;;
	k)
		DO_KERNEL="-k"
		;;
	l)
		DO_LOCAL="-l ${OPTARG}"
		;;
	M)
		mirror_abi
		exit 0
		;;
	m)
		if [ -n "${OPTARG}" ]; then
			DO_MIRRORURL="-m ${OPTARG}"
		fi
		;;
	N)
		DO_FLAVOUR="-N ${OPTARG}"
		;;
	n)
		if [ -n "${OPTARG}" ]; then
			DO_MIRRORDIR="-n ${OPTARG}"
		fi
		;;
	P)
		DO_FORCE="-f"
		DO_PKGS="-P"
		DO_KERNEL=
		DO_BASE=
		;;
	p)
		DO_PKGS="-p"
		;;
	r)
		DO_RELEASE="-r ${OPTARG}"
		RELEASE=${OPTARG}
		;;
	s)
		DO_SKIP="-s"
		;;
	t)
		DO_TYPE="-t ${OPTARG}"
		;;
	u)
		DO_UPGRADE="-u"
		;;
	v)
		DO_VERSION="-v"
		;;
	*)
		echo "Usage: man opnsense-update" >&2
		exit 1
		;;
	esac
done

shift $((${OPTIND} - 1))

if [ -n "${*}" ]; then
	echo "Arguments are not supported" >&2
	exit 1
fi

if [ -n "${DO_VERSION}" ]; then
	if [ -n "${DO_BASE}" ]; then
		echo ${INSTALLED_BASE}
	elif [ -n "${DO_KERNEL}" ]; then
		echo ${INSTALLED_KERNEL}
	else
		echo ${VERSION}-${ARCH}
	fi
	exit 0
fi

if [ -n "${DO_TYPE}" ]; then
	OLD=$(cat /usr/local/opnsense/version/opnsense.name)
	NEW=${DO_TYPE#"-t "}

	if [ "${OLD}" = "${NEW}" -a -z "${DO_FORCE}" ]; then
		echo "The package type '${OLD}' is already installed."
	else
		# cache packages in case something goes wrong
		${PKG} fetch -y ${OLD} ${NEW}

		# strip vital flag from installed package type
		${PKG} set -yv 0 ${OLD}

		# attempt to install the new package type and...
		if ! ${PKG} install -y ${DO_FORCE} ${NEW}; then
			NEW=${OLD}
		fi

		# ...recover in both cases as pkg(8) seems to
		# have problems in a few edge cases that involve
		# different package dependencies between types
		if ! ${PKG} query %n ${NEW} > /dev/null; then
			# always force the second install
			${PKG} install -fy ${NEW}
		fi

		# set exit code based on transition status
		[ "${OLD}" != "${NEW}" ]
	fi
fi

if [ -z "${DO_TYPE}${DO_KERNEL}${DO_BASE}${DO_PKGS}" ]; then
	# default is enable all
	DO_KERNEL="-k"
	DO_BASE="-b"
	DO_PKGS="-p"
fi

if [ -n "${DO_CHECK}" ]; then
	if [ -n "${DO_KERNEL}" ]; then
		if [ "${VERSION}-${ARCH}" != "${INSTALLED_KERNEL}" ]; then
			exit 0
		fi
	fi
	if [ -n "${DO_BASE}" ]; then
		if [ "${VERSION}-${ARCH}" != "${INSTALLED_BASE}" ]; then
			exit 0
		fi
	fi
	# will not check DO_PKGS, different approach
	exit 1
fi

if [ -n "${DO_DEFAULTS}" ]; then
	# restore origin.conf before potential replace
	cp ${ORIGIN}.sample ${ORIGIN}
fi

if [ -n "${DO_MIRRORDIR}" ]; then
	# replace the package repo name
	sed -i '' '/'"${URL_KEY}"'/s/${ABI}.*/${ABI}\/'"${DO_MIRRORDIR#"-n "}"'\",/' ${ORIGIN}
fi

if [ -n "${DO_MIRRORURL}" ]; then
	# replace the package repo location
	sed -i '' '/'"${URL_KEY}"'/s/pkg\+.*${ABI}/pkg\+'"${DO_MIRRORURL#"-m "}"'\/${ABI}/' ${ORIGIN}
fi

if [ -n "${DO_SKIP}" ]; then
	# only invoke flavour and mirror replacement
	exit 0
fi

# if no release was selected we use the embedded defaults
if [ -z "${RELEASE}" ]; then
	RELEASE=${VERSION}
fi

if [ "${DO_BASE}" = "-B" ]; then
	if [ ! -f "${WORKPREFIX}/.base.pending" ]; then
		# must error out to prevent reboot
		exit 1
	fi

	RELEASE=$(cat "${WORKPREFIX}/.base.pending")
	WORKDIR=${PENDINGDIR}

	rm -f "${WORKPREFIX}/.base.pending"
elif [ "${DO_PKGS}" = "-P" ]; then
	if [ ! -f "${WORKPREFIX}/.pkgs.pending" ]; then
		# must error out to prevent reboot
		exit 1
	fi

	RELEASE=$(cat "${WORKPREFIX}/.pkgs.pending")
	WORKDIR=${PENDINGDIR}

	if [ -f "${WORKPREFIX}/.pkgs.insecure" ]; then
		DO_INSECURE="-i"
	fi

	rm -f "${WORKPREFIX}/.pkgs.pending"
	rm -f "${WORKPREFIX}/.pkgs.insecure"
elif [ -n "${DO_LOCAL}" ]; then
	WORKDIR=${DO_LOCAL#"-l "}
fi

if [ "${DO_PKGS}" = "-p" -a -z "${DO_UPGRADE}" ]; then
	# clean up deferred sets that could be there
	rm -rf ${PENDINGDIR}/packages-*

	if ${PKG} update ${DO_FORCE} && ${PKG} upgrade -y ${DO_FORCE}; then
		${PKG} autoremove -y
		${PKG} clean -ya
	else
		# cannot continue after failed upgrade
		exit 1
	fi

	if [ -n "${DO_BASE}${DO_KERNEL}" ]; then
		# script may have changed, relaunch...
		opnsense-update ${DO_BASE} ${DO_KERNEL} ${DO_LOCAL} \
		    ${DO_FORCE} ${DO_RELEASE} ${DO_DEFAULTS} \
		    ${DO_MIRRORDIR} ${DO_MIRRORURL} ${DO_HIDE} \
		    ${DO_ABI}
	fi

	# stop here to prevent the second pass
	exit 0
fi

if [ -z "${DO_FORCE}" ]; then
	# disable kernel update if up-to-date
	if [ "${RELEASE}-${ARCH}" = "${INSTALLED_KERNEL}" -a \
	    -n "${DO_KERNEL}" ]; then
		DO_KERNEL=
	fi

	# disable base update if up-to-date
	if [ "${RELEASE}-${ARCH}" = "${INSTALLED_BASE}" -a \
	    -n "${DO_BASE}" ]; then
		DO_BASE=
	fi

	# nothing to do
	if [ -z "${DO_KERNEL}${DO_BASE}${DO_PKGS}" ]; then
		echo "Your system is up to date."
		exit 0
	fi
fi

FLAVOUR="Base"
if [ -n "${DO_FLAVOUR}" ]; then
	FLAVOUR=${DO_FLAVOUR#"-N "}
elif [ -f ${OPENSSL} ]; then
	FLAVOUR=$(${OPENSSL} version | awk '{ print $1 }')
fi

PACKAGESSET=packages-${RELEASE}-${FLAVOUR}-${ARCH}.tar
OBSOLETESET=base-${RELEASE}-${ARCH}.obsolete
KERNELSET=kernel-${RELEASE}-${ARCH}.txz
BASESET=base-${RELEASE}-${ARCH}.txz

# This is a currently inflexible: with it
# we cannot escape the sets directory, so
# that e.g. using a "snapshots" directory
# for testing is not easily possible.
MIRROR="$(mirror_abi)/sets"

fetch_set()
{
	STAGE1="opnsense-fetch ${DO_INSECURE} -a -T 30 -q -o ${WORKDIR}/${1}.sig ${MIRROR}/${1}.sig"
	STAGE2="opnsense-fetch ${DO_INSECURE} -a -T 30 -q -o ${WORKDIR}/${1} ${MIRROR}/${1}"
	STAGE3="opnsense-verify -q ${WORKDIR}/${1}"

	if [ -n "${DO_LOCAL}" ]; then
		# already fetched, just test
		STAGE1="test -f ${WORKDIR}/${1}.sig"
		STAGE2="test -f ${WORKDIR}/${1}"
	fi

	if [ -n "${DO_INSECURE}" ]; then
		# no signature, no cry
		STAGE1=":"
		STAGE3=":"
	fi

	echo -n "Fetching ${1}: ."

	mkdir -p ${WORKDIR} && ${STAGE1} && ${STAGE2} && \
	    ${STAGE3} && echo " done" && return

	echo " failed"
	exit 1
}

install_kernel()
{
	KLDXREF="kldxref ${KERNELDIR}"

	if [ -n "${DO_UPGRADE}" ]; then
		KLDXREF=":"
	fi

	echo -n "Installing ${KERNELSET}..."

	rm -rf ${KERNELDIR}.old && \
	    mkdir -p ${KERNELDIR} && \
	    mv ${KERNELDIR} ${KERNELDIR}.old && \
	    tar -C/ -xpf ${WORKDIR}/${KERNELSET} && \
	    ${KLDXREF} && echo " done" && return

	echo " failed"
	exit 1
}

install_base()
{
	NOSCHGDIRS="/bin /sbin /lib /libexec /usr/bin /usr/sbin /usr/lib /var/empty"

	echo -n "Installing ${BASESET}..."

	mkdir -p ${NOSCHGDIRS} && \
	    chflags -R noschg ${NOSCHGDIRS} && \
	    tar -C/ -xpf ${WORKDIR}/${BASESET} \
	    --exclude="./etc/group" \
	    --exclude="./etc/master.passwd" \
	    --exclude="./etc/passwd" \
	    --exclude="./etc/shells" \
	    --exclude="./etc/ttys" \
	    --exclude="./etc/rc" \
	    --exclude="./etc/rc.shutdown" && \
	    kldxref ${KERNELDIR} && \
	    echo " done" && return

	echo " failed"
	exit 1
}

install_obsolete()
{
	echo -n "Installing ${OBSOLETESET}..."

	while read FILE; do
		rm -f ${FILE}
	done < ${WORKDIR}/${OBSOLETESET}

	echo " done"
}

install_pkgs()
{
	echo "Installing ${PACKAGESSET}..."

	# We can't recover from this replacement, but
	# since the manual says we require a reboot
	# after `-P', it is to be considered a feature.
	sed -i '' '/'"${URL_KEY}"'/s/pkg\+.*/file:\/\/\/var\/cache\/opnsense-update\/.sets.pending\/packages-'"${RELEASE}"'\",/' ${ORIGIN}

	if [ -n "${DO_INSECURE}" ]; then
		# Insecure meant we didn't have any sets signatures,
		# and now the packages are internally signed again,
		# so we need to disable its native verification, too.
		sed -i '' '/'"${SIG_KEY}"'/s/\"fingerprints\"/\"none\"/' ${ORIGIN}
	fi

	# run full upgrade from the local repository
	${PKG} unlock -ay
	if ${PKG} upgrade -fy; then
		${PKG} autoremove -y
		${PKG} clean -ya
	fi
}

if [ "${DO_PKGS}" = "-p" ]; then
	fetch_set ${PACKAGESSET}
fi

if [ "${DO_BASE}" = "-b" ]; then
	fetch_set ${OBSOLETESET}
	fetch_set ${BASESET}
fi

if [ "${DO_KERNEL}" = "-k" ]; then
	fetch_set ${KERNELSET}
fi

if [ "${DO_KERNEL}" = "-k" ] || \
    [ -n "${DO_BASE}" -a -z "${DO_UPGRADE}" ] || \
    [ "${DO_PKGS}" = "-P" -a -z "${DO_UPGRADE}" ]; then
	echo "!!!!!!!!!!!! ATTENTION !!!!!!!!!!!!!!!"
	echo "! A critical upgrade is in progress. !"
	echo "! Please do not turn off the system. !"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
fi

if [ "${DO_PKGS}" = "-p" -a -n "${DO_UPGRADE}" ]; then
	echo -n "Extracting ${PACKAGESSET}..."

	# clean up from a potential previous run
	rm -rf ${PENDINGDIR}/packages-*
	mkdir -p ${PENDINGDIR}/packages-${RELEASE}
	${PKG} clean -qya

	# extract packages to avoid unpacking after reboot
	tar -C${PENDINGDIR}/packages-${RELEASE} -xpf \
	    ${WORKDIR}/${PACKAGESSET}

	# add action marker for next run
	echo ${RELEASE} > "${WORKPREFIX}/.pkgs.pending"

	if [ -n "${DO_INSECURE}" ]; then
		touch "${WORKPREFIX}/.pkgs.insecure"
	fi

	echo " done"
fi

if [ "${DO_BASE}" = "-b" -a -n "${DO_UPGRADE}" ]; then
	echo -n "Extracting ${BASESET}..."

	# clean up from a potential previous run
	rm -rf ${PENDINGDIR}/base-*
	mkdir -p ${PENDINGDIR}

	# push pending base update to deferred
	mv ${WORKDIR}/${BASESET} ${PENDINGDIR}

	echo " done"
	echo -n "Extracting ${OBSOLETESET}..."

        mv ${WORKDIR}/${OBSOLETESET} ${PENDINGDIR}

	# add action marker for next run
	echo ${RELEASE} > "${WORKPREFIX}/.base.pending"

	echo " done"
fi

if [ "${DO_KERNEL}" = "-k" ]; then
	install_kernel
fi

if [ -n "${DO_BASE}" -a -z "${DO_UPGRADE}" ]; then
	if [ "${DO_BASE}" = "-B" ]; then
		mkdir -p ${WORKDIR}/base-freebsd-version
		tar -C${WORKDIR}/base-freebsd-version -xpf \
		    ${WORKDIR}/${BASESET} ./bin/freebsd-version

		BASE_VER=$(base_version ${WORKDIR}/base-freebsd-version)
		KERNEL_VER=$(kernel_version)

		BASE_VER=${BASE_VER%%-*}
		KERNEL_VER=${KERNEL_VER%%-*}

		if [ "${BASE_VER}" != "${KERNEL_VER}" ]; then
			echo "Version number mismatch, aborting."
			echo "    Kernel: ${KERNEL_VER}"
			echo "    Base:   ${BASE_VER}"
			# Clean all the pending updates, so that
			# packages are not upgraded as well.
			empty_cache
			exit 1
		fi
	fi

	install_base
	install_obsolete

	# clean up deferred sets that could be there
	rm -rf ${PENDINGDIR}/base-*
fi

if [ "${DO_PKGS}" = "-P" -a -z "${DO_UPGRADE}" ]; then
	install_pkgs

	# clean up deferred sets that could be there
	rm -rf ${PENDINGDIR}/packages-*
fi

if [ -n "${DO_HIDE}" ]; then
	# hide the version info in case it was requested
	mkdir -p ${VERSIONDIR}

	if [ -n "${DO_KERNEL}" ]; then
		echo ${VERSION}-${ARCH} > ${VERSIONDIR}/kernel
	fi

	if [ -n "${DO_BASE}" -a -z "${DO_UPGRADE}" ]; then
		echo ${VERSION}-${ARCH} > ${VERSIONDIR}/base
	fi
fi

if [ -z "${DO_LOCAL}" ]; then
	rm -rf ${WORKPREFIX}/*
fi

echo "Please reboot."
