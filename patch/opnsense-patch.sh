shift $((${OPTIND} - 1))
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