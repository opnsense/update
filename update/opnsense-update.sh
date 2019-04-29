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

if [ "$(id -u)" != "0" ]; then
	echo "Must be root." >&2
	exit 1
fi

SIG_KEY="^[[:space:]]*signature_type:[[:space:]]*"
URL_KEY="^[[:space:]]*url:[[:space:]]*"
VERSIONDIR="/usr/local/opnsense/version"
WORKPREFIX="/var/cache/opnsense-update"
OPENSSL="/usr/local/bin/openssl"
DEBUGDIR="/usr/lib/debug"
KERNELDIR="/boot/kernel"
TEE="/usr/bin/tee -a"
PRODUCT="OPNsense"
PKG="pkg-static"
VERSION="19.1.7"

ORIGIN="/usr/local/etc/pkg/repos/${PRODUCT}.conf"
PENDINGDIR="${WORKPREFIX}/.sets.pending"
PIPEFILE="${WORKPREFIX}/.upgrade.pipe"
LOGFILE="${WORKPREFIX}/.upgrade.log"
WORKDIR="${WORKPREFIX}/${$}"
ARCH=$(uname -p)

if [ ! -f ${ORIGIN} ]; then
	echo "Missing ${ORIGIN}" >&2
	exit 1
fi

INSTALLED_BASE=
if [ -f ${VERSIONDIR}/base ]; then
	INSTALLED_BASE=$(cat ${VERSIONDIR}/base)
fi

LOCKED_BASE=
if [ -f ${VERSIONDIR}/base.lock ]; then
	LOCKED_BASE=1
fi

LOCKED_PKGS=
if [ -f ${VERSIONDIR}/core.lock ]; then
	LOCKED_PKGS=1
fi

INSTALLED_KERNEL=
if [ -f ${VERSIONDIR}/kernel ]; then
	INSTALLED_KERNEL=$(cat ${VERSIONDIR}/kernel)
fi

LOCKED_KERNEL=
if [ -f ${VERSIONDIR}/kernel.lock ]; then
	LOCKED_KERNEL=1
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
	if [ -z "${MIRROR}" ]; then
		echo "Mirror read failed." >&2
		exit 1
	fi
	ABI=$(opnsense-verify -a)
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
DO_VERBOSE=
DO_KERNEL=
DO_UNLOCK=
DO_LOCAL=
DO_LOCK=
DO_FORCE=
DO_CHECK=
DO_BASE=
DO_PKGS=
DO_SKIP=
DO_SIZE=
DO_TYPE=
DO_ABI=

while getopts a:BbcdefikLl:Mm:N:n:Ppr:Sst:TUuvV OPT; do
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
	i)
		DO_INSECURE="-i"
		;;
	k)
		DO_KERNEL="-k"
		;;
	L)
		DO_LOCK="-L"
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
	S)
		DO_SIZE="-S"
		;;
	t)
		DO_TYPE="-t ${OPTARG}"
		;;
	T)
		DO_TYPE="-T"
		;;
	U)
		DO_UNLOCK="-U"
		;;
	u)
		DO_UPGRADE="-u"
		;;
	V)
		DO_VERBOSE="-V"
		;;
	v)
		echo ${VERSION}
		exit 0
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

if [ -n "${DO_VERBOSE}" ]; then
	set -x
fi

if [ "${DO_TYPE}" = "-T" ]; then
	if [ -n "${DO_BASE}" -a -n "${LOCKED_BASE}" ]; then
		exit 1
	elif [ -n "${DO_KERNEL}" -a -n "${LOCKED_KERNEL}" ]; then
		exit 1
	elif [ -n "${DO_PKGS}" -a -n "${LOCKED_PKGS}" ]; then
		exit 1
	fi
	exit 0
fi

if [ -z "${DO_TYPE}${DO_KERNEL}${DO_BASE}${DO_PKGS}" ]; then
	# default is enable all
	DO_KERNEL="-k"
	DO_BASE="-b"
	DO_PKGS="-p"
fi

if [ -n "${DO_LOCK}" ]; then
	mkdir -p ${VERSIONDIR}
	if [ -n "${DO_KERNEL}" ]; then
		touch ${VERSIONDIR}/kernel.lock
	fi
	if [ -n "${DO_BASE}" ]; then
		touch ${VERSIONDIR}/base.lock
	fi
	if [ -n "${DO_PKGS}" ]; then
		touch ${VERSIONDIR}/core.lock
	fi
	exit 0
elif [ -n "${DO_UNLOCK}" ]; then
	if [ -n "${DO_KERNEL}" ]; then
		rm -f ${VERSIONDIR}/kernel.lock
	fi
	if [ -n "${DO_BASE}" ]; then
		rm -f ${VERSIONDIR}/base.lock
	fi
	if [ -n "${DO_PKGS}" ]; then
		rm -f ${VERSIONDIR}/core.lock
	fi
	exit 0
fi

# DO_CHECK is not included, must be forced because we need both modes
if [ -z "${DO_FORCE}${DO_SIZE}" ]; then
	# disable kernel if locked
	if [ -n "${DO_KERNEL}" -a -n "${LOCKED_KERNEL}" -a \
	    -z "${DO_UPGRADE}" ]; then
		echo "Kernel locked at ${INSTALLED_KERNEL}, skipping."
		DO_KERNEL=
	fi

	# disable base if locked
	if [ -n "${DO_BASE}" -a -n "${LOCKED_BASE}" -a \
	    -z "${DO_UPGRADE}" ]; then
		echo "Base locked at ${INSTALLED_BASE}, skipping."
		DO_BASE=
	fi

	# disable packages if locked
	if [ -n "${DO_PKGS}" -a -n "${LOCKED_PKGS}" -a \
	    -z "${DO_UPGRADE}" ]; then
		echo "Packages locked, skipping."
		DO_PKGS=
		DO_TYPE=
	fi
fi

if [ -n "${DO_TYPE}" ]; then
	OLD=$(opnsense-version -n)
	NEW=${DO_TYPE#"-t "}

	if [ "${OLD}" = "${NEW}" -a -z "${DO_FORCE}" ]; then
		echo "The package '${OLD}' is already installed."
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

if [ -n "${DO_CHECK}" ]; then
	if [ -n "${DO_KERNEL}" ]; then
		if [ "${VERSION}" != "${INSTALLED_KERNEL}" ]; then
			exit 0
		fi
	fi
	if [ -n "${DO_BASE}" ]; then
		if [ "${VERSION}" != "${INSTALLED_BASE}" ]; then
			exit 0
		fi
	fi
	# will not check DO_PKGS, different approach
	exit 1
fi

if [ -n "${DO_DEFAULTS}" ]; then
	# restore default before potential replace
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

if [ "${DO_PKGS}" = "-p" -a -z "${DO_UPGRADE}${DO_SIZE}" ]; then
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
		    ${DO_MIRRORDIR} ${DO_MIRRORURL} ${DO_ABI}
	fi

	# stop here to prevent the second pass
	exit 0
fi

FLAVOUR="Base"
if [ -n "${DO_FLAVOUR}" ]; then
	FLAVOUR=${DO_FLAVOUR#"-N "}
elif [ -f ${OPENSSL} ]; then
	FLAVOUR=$(${OPENSSL} version | awk '{ print $1 }')
fi

PACKAGESSET=packages-${RELEASE}-${FLAVOUR}-${ARCH}.tar
KERNELSET=kernel-${RELEASE}-${ARCH}.txz
BASESET=base-${RELEASE}-${ARCH}.txz

MIRROR="$(mirror_abi)/sets"

if [ -n "${DO_SIZE}" ]; then
	if [ -n "${DO_BASE}" ]; then
		BASE_SIZE=$(fetch -s ${MIRROR}/${BASESET} 2> /dev/null)
		echo ${BASE_SIZE}
	elif [ -n "${DO_KERNEL}" ]; then
		KERNEL_SIZE=$(fetch -s ${MIRROR}/${KERNELSET} 2> /dev/null)
		echo ${KERNEL_SIZE}
	elif [ -n "${DO_PKGS}" ]; then
		PKGS_SIZE=$(fetch -s ${MIRROR}/${PACKAGESSET} 2> /dev/null)
		echo ${PKGS_SIZE}
	fi
	exit 0
fi

if [ -z "${DO_FORCE}" ]; then
	# disable kernel update if up-to-date
	if [ "${RELEASE}" = "${INSTALLED_KERNEL}" -a -n "${DO_KERNEL}" ]; then
		DO_KERNEL=
	fi

	# disable base update if up-to-date
	if [ "${RELEASE}" = "${INSTALLED_BASE}" -a -n "${DO_BASE}" ]; then
		DO_BASE=
	fi

	# nothing to do
	if [ -z "${DO_KERNEL}${DO_BASE}${DO_PKGS}" ]; then
		echo "Your system is up to date."
		exit 0
	fi
fi

exit_msg()
{
	if [ -n "${1}" ]; then
		echo "${1}"
	fi

	exit 1
}

fetch_set()
{
	STAGE1="opnsense-fetch -a -T 30 -q -o ${WORKDIR}/${1}.sig ${MIRROR}/${1}.sig"
	STAGE2="opnsense-fetch -a -T 30 -q -o ${WORKDIR}/${1} ${MIRROR}/${1}"
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

	if ! mkdir -p ${WORKDIR}; then
		exit_msg " failed, mkdir error ${?}"
	fi

	if ! ${STAGE1}; then
		exit_msg " failed, no signature found"
	fi

	if ! ${STAGE2}; then
		exit_msg " failed, no update found"
	fi

	if [ -n "${DO_VERBOSE}" ]; then
		if ! ${STAGE3}; then
			# message did print already
			exit_msg
		fi
	else
		if ! ${STAGE3} 2> /dev/null; then
			exit_msg " failed, signature invalid"
		fi
	fi

	echo " done"
}

install_kernel()
{
	KLDXREF="kldxref ${KERNELDIR}"

	if [ -n "${DO_UPGRADE}" ]; then
		KLDXREF=":"
	fi

	echo -n "Installing ${KERNELSET}..."

	if ! mkdir -p ${KERNELDIR} ${KERNELDIR}.old ${DEBUGDIR}${KERNELDIR}; then
		exit_msg " failed, mkdir error ${?}"
	fi

	if ! rm -r ${KERNELDIR}.old ${DEBUGDIR}${KERNELDIR}; then
		exit_msg " failed, rm error ${?}"
	fi

	if ! mv ${KERNELDIR} ${KERNELDIR}.old; then
		exit_msg " failed, mv error ${?}"
	fi

	if ! tar -C / -xpf ${WORKDIR}/${KERNELSET}; then
		exit_msg " failed, tar error ${?}"
	fi

	if ! ${KLDXREF}; then
		exit_msg " failed, kldxref error ${?}"
	fi

	echo " done"
}

install_base()
{
	NOSCHGDIRS="/bin /sbin /lib /libexec /usr/bin /usr/sbin /usr/lib /var/empty"

	echo -n "Installing ${BASESET}..."

	if ! mkdir -p ${NOSCHGDIRS}; then
		exit_msg " failed, mkdir error ${?}"
	fi

	if ! chflags -R noschg ${NOSCHGDIRS}; then
		exit_msg " failed, chflags error ${?}"
	fi

	if ! tar -C / -xpf ${WORKDIR}/${BASESET} \
	    --exclude="^etc/group" \
	    --exclude="^etc/master.passwd" \
	    --exclude="^etc/motd" \
	    --exclude="^etc/passwd" \
	    --exclude="^etc/pwd.db" \
	    --exclude="^etc/rc" \
	    --exclude="^etc/rc.shutdown" \
	    --exclude="^etc/shells" \
	    --exclude="^etc/spwd.db" \
	    --exclude="^etc/ttys" \
	    --exclude="^proc" \
	    --exclude="^var/cache/pkg" \
	    --exclude="^var/crash" \
	    --exclude="^var/db/pkg"; then
		exit_msg " failed, tar error ${?}"
	fi

	if ! kldxref ${KERNELDIR}; then
		exit_msg " failed, kldxref error ${?}"
	fi

	if [ ! -f ${VERSIONDIR}/base.obsolete ]; then
		exit_msg " failed, no base.obsolete found"
	fi

	while read FILE; do
		rm -f ${FILE}
	done < ${VERSIONDIR}/base.obsolete

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

	# prepare log file and pipe
	mkdir -p ${WORKPREFIX}
	: > ${LOGFILE}
	rm -f ${PIPEFILE}
	mkfifo ${PIPEFILE}

	# unlock all to avoid dependency stalls
	${TEE} ${LOGFILE} < ${PIPEFILE} &
	${PKG} unlock -ay 2>&1 > ${PIPEFILE}

	# run full upgrade from the local repository
	${TEE} ${LOGFILE} < ${PIPEFILE} &
	if ${PKG} upgrade -fy -r ${PRODUCT} 2>&1 > ${PIPEFILE}; then
		${TEE} ${LOGFILE} < ${PIPEFILE} &
		${PKG} autoremove -y 2>&1 > ${PIPEFILE}
		${TEE} ${LOGFILE} < ${PIPEFILE} &
		${PKG} clean -ya 2>&1 > ${PIPEFILE}
	fi
}

if [ "${DO_PKGS}" = "-p" ]; then
	if [ -z "${DO_FORCE}" -o -n "${DO_UPGRADE}" ]; then
		rm -f ${VERSIONDIR}/core.lock
	fi
	fetch_set ${PACKAGESSET}
fi

if [ "${DO_BASE}" = "-b" ]; then
	if [ -z "${DO_FORCE}" -o -n "${DO_UPGRADE}" ]; then
		rm -f ${VERSIONDIR}/base.lock
	fi
	fetch_set ${BASESET}
fi

if [ "${DO_KERNEL}" = "-k" ]; then
	if [ -z "${DO_FORCE}" -o -n "${DO_UPGRADE}" ]; then
		rm -f ${VERSIONDIR}/kernel.lock
	fi
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

	# clean up deferred sets that could be there
	rm -rf ${PENDINGDIR}/base-*
fi

if [ "${DO_PKGS}" = "-P" -a -z "${DO_UPGRADE}" ]; then
	install_pkgs

	# clean up deferred sets that could be there
	rm -rf ${PENDINGDIR}/packages-*
fi

if [ -z "${DO_LOCAL}" ]; then
	rm -rf ${WORKPREFIX}/*
fi

echo "Please reboot."
