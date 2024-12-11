CONFIG="core"
	*core*)
		CONFIG="core"
	*installer*)
		CONFIG="installer"
	*plugins*)
		CONFIG="plugins"
	*update*)
		CONFIG="update"
		if [ "${FILE%-*}" != ${CONFIG} ]; then
		if [ "${FILE%-*}" != ${CONFIG} ]; then
	# only allow patching with the right -a option set
		return
	fi

	# error to the user if -a did not match
	URL="${ARG#"${SITE}/"}"
	if [ "${URL}" != ${ARG} ]; then
		echo "Account '${ACCOUNT}' does not match given URL." >&2
		exit 1

	# continue here with a hash-only argument
	WANT="${CONFIG}-${ARG}"
	ARG=${CONFIG}-${ARG} # reconstruct file name on disk
			if [ "${CONFIG}" = "installer" -o "${CONFIG}" == "update" ]; then