#! /bin/bash

#####################
# Helper functions #
#####################

usage() {
	echo "Usage: ./stress_cached [-l <path>]"
	echo "                       [-test <i>] [-ff <i>] [-until <i>]"
	echo "                       [-bench <p>] [-seed <n>]"
	echo "                       [-v <i>] [-p <n>] [-y] [-c] [-h]"
	echo ""
	echo "Options: -l <path>:  store logs in this path"
	echo "                     default: ${ARCH_SCRIPTS}/log/stress_cached"
	echo "                     permitted: ${HOME}/* or /tmp/*"
	echo "         -test <i>:  run only test <i>"
	echo "         -ff <i>:    fast-forward to test <i>, run every test"
	echo "                     from there on"
	echo "         -until <i>: run every test until AND test <i>"
	echo "         -bench <p>: define number of bench instances"
	echo "         -seed <n>:  use <n> as a seed for the test (9-digits"
	echo "                     only)"
	echo "         --filed:    use filed instead of sosd for storage"
	echo "         -v <l>:     set verbosity level to <l>"
	echo "         -p <n>:     profile CPU usage of cached using <n>"
	echo "                     samples"
	echo "         -w:         warm-up before writing to cached"
	echo "         -y:         do not wait between tests"
	echo "         -c:         just clean the segment"
	echo "         -h:         print this message"
	echo ""
	echo "---------------------------------------------------------------------"
	echo "Additional info:"
	echo ""
	echo "* None of the above options needs to be used. By default,"
	echo "  stress_cached will iterate the list of tests and pause between "
	echo "  each one so that the user can take a look at the logs."
	echo ""
	echo "* If the user has not given a seed, stress_cached will pick a random "
	echo "  seed value."
	echo ""
	echo "* The -ff and -until options can be used together to run tests"
	echo "  within a range."
	echo ""
	echo "* The bench instances will all do the same job. The difference is"
	echo "  that they will wait in a different port."
	echo ""
	echo "* An easy way to check out the output would be to start 3 terminals"
	echo "  and simply have them do: tail -F /var/log/stress_cached/cached*"
	echo "  (or bench*, filed*). Thus, when a file is rm'ed or a new file"
	echo "  with the sam prefix has been added, tail will read it and you won't"
	echo "  have to do anything."
	echo ""
	echo "* You can override the predefined-values of a test option by"
	echo "  passing an environment variable like FORCE_*, where '*' can be"
	echo "  a test option (WCP, CACHE_SIZE, BENCH_SIZE etc.). Then, the"
	echo "  value of FORCE_* is used to override the pre-defined option"
	echo "  values."
	echo ""
	echo "  e.g. FORCE_BLOCK_SIZE='4k 666k' ./stress_cached.sh"
	echo ""
}

init_binaries_and_folders() {
	PITHOS_FOLDER=${ARCH_SCRIPTS}/pithos/pithos
	ARCHIP_FOLDER=${ARCH_SCRIPTS}/pithos/archip
	if [[ -z $LOG_FOLDER ]]; then
		LOG_FOLDER=${ARCH_SCRIPTS}/log/stress_cached
	fi

	SOSD_POOL=cached-blocks

	LD_PRELOAD_PATH="LD_PRELOAD=${XSEG}/sys/user/libxseg.so"
	XSEG_BIN="${LD_PRELOAD_PATH} ${XSEG}/peers/user/xseg"
	BENCH_BIN="${LD_PRELOAD_PATH} ${XSEG}/peers/user/archip-bench"
	CACHED_BIN="${LD_PRELOAD_PATH} ${XSEG}/peers/user/archip-cached"
	FILED_BIN="${LD_PRELOAD_PATH} ${XSEG}/peers/user/archip-filed"
	SOSD_BIN="${LD_PRELOAD_PATH} ${XSEG}/peers/user/archip-sosd"

	# Create log folder
	mkdir -p ${LOG_FOLDER}
}

# The following function iterates the test options and tries to match them with
# an environment variable called FORCE_<TEST_OPTION> e.g. FORCE_WCP,
# FORCE_THREADS etc.
# If it finds one, it informs the user that the values have been overriden.
override_test_options() {
	for OPT in $TEST_OPTIONS; do
		FORCE_OPT="FORCE_"${OPT}
		if [[ -n ${!FORCE_OPT} ]]; then
			OPT_VALS=${OPT}"_VALS"
			eval ${OPT_VALS}='${!FORCE_OPT}'
			orn_echo "Overriding ${OPT}: '${!OPT_VALS}'"
		fi
	done
}

init_logs() {
	local peer

	for peer in bench-warmup bench-write bench-read cached $STORAGE; do
		LOG=${LOG_FOLDER}/"${peer}"${1}".log"

		# Truncate previous logs
		cat /dev/null > $LOG

		echo "" >> $LOG
		blu_echo "******************" >> $LOG
		blu_echo " TEST ${I} STARTED" >> $LOG
		blu_echo "******************" >> $LOG
		echo "" >> $LOG
	done
}

parse_args() {
	# ${1} is for threads
	if [[ ${1} = 'single' ]]; then
		T_SOSD=1
		T_FILED=64
		T_CACHED=1
		T_BENCH=1
	elif [[ ${1} = 'multi' ]]; then
		T_SOSD=1
		T_FILED=64
		T_CACHED=4
		T_BENCH=1
	else
		red_echo "${1} is not a valid thread option"
		exit
	fi

	# ${2} is for cache size
	CACHE_SIZE=$( python -c "print int(${CACHE_OBJECTS} * ${2%x} * 4)" )'M'
	if [[ ${CACHE_OBJECTS} = 4 ]]; then
		NR_OPS=4
	else
		NR_OPS=16
	fi

	# ${3} and ${4} is for bench size and request cap
	BENCH_SIZE=$( python -c "print int(${CACHE_SIZE%M} * ${3%x})" )'M'
	if [[ ${4} = 'bounded' ]]; then
		RC=''
	elif [[ ${4} = 'holyshit' ]]; then
		local requests
		requests=$(( ${BENCH_SIZE%M} / 4 ))'K'

		RC="-rc ${requests}"
		BENCH_SIZE="999G"
	else
		red_echo "${4} is not a valid bench size option"
		exit
	fi

	# ${5} shows if cached is used in this test.
	# If cached is not used, unset "next ports for bench, so that requests
	# can go directly to storage.
	if [[ $5 == "no" ]]; then
		restore_bench_ports
	fi

}

# Depending on the number of bench instances, we calculate what are the
# appropriate bench ports for them.
# We start assigning ports from port 2 and on. For example, if there are 3 bench
# instances, BENCH_PORTS will contain this string: "2 3 4"
create_bench_ports() {
	local i
	local new_port
	if [[ "${BENCH_INSTANCES}" -gt 14 ]]; then
		red_echo "-bench ${BENCH_INSTANCES}: Not enough ports for that"
		exit
	elif [[ "${BENCH_INSTANCES}" -gt 0 ]]; then
		for (( i=1; i<="${BENCH_INSTANCES}"; i++ )); do
			new_port=$(( $i + 1 ))
			BENCH_PORTS=${BENCH_PORTS}" ${new_port}"
		done
	else
		red_echo "-bench ${BENCH_INSTANCES}: Invalid argument"
		exit
	fi
}

# Create a random (or user-provided) 9-digit seed
create_seed() {
	# if $1 is not empty then the user has provided a seed value
	if [[ -n $1 ]]; then
		SEED=$(($1 % 1000000000))
		if [[ $1 != $SEED ]]; then
			red_echo "Provided seed was larger than expected:"
			red_echo "\tOnly its first 9 digits will be used."
		fi
		return
	fi
	SEED=$(od -vAn -N4 -tu4 < /dev/urandom)
	SEED=$(($SEED % 1000000000))
}

# This is a bit tricky so an explanation is needed:
#
# Each peer command is a single-quoted string with non-evaluated variables. This
# string will be passed later on to 'eval' in order to start each peer. So,
# granted this input, we want to print the command that will be fed to eval, but
# with evaluated variables, wrapped at 54 characters, tabbed and with a back-
# slash appended to the end of every line.
#
# So, if our input was: 'a very nice cow' our output (wrapped at 4 chars) should
# be:
#
# a \
#     very \
#     nice \
#     cow
#
# And now to the gritty details on how we do that:
# 1) First, we append a special character (#) at the end of the peer command.
# 2) Then, we add at the start a new string ("echo "). This converts the
#    peer command to an echo command in a string.
# 2) The echo command is passed to eval. This way, eval will not run the peer
#    command but will simply evaluate the variables in the string and echo them.
# 3) Then, we pipe the output to fmt, which wraps it at 54 chars and tabs every
#    line but the first one. Note that every new line will be printed separately
# 4) The output is then fed to sed, which appends a back-slash at the end of
#    each line.
# 5) Finally, the output is fed for one last time to sed, which removes the
#    backslash from the last line (the line with the (#) character.
print_test() {
	local echo=echo
	local shade_text
	local unshade_text
	if [[ $USE_CACHED == "no" ]]; then
		shade_text=shade_text
		restore_text=restore_text
	fi

	echo ""
	grn_echo "Summary of Test ${I_TEST} (SEED ${SEED}):"
	echo "WCP=${WCP} THREADS=${THREADS} IODEPTH=${IODEPTH}"
	$shade_text
	echo -n "CACHE_OBJECTS=${CACHE_OBJECTS} CACHE_SIZE=${CACHE_SIZE}"
	echo "(${CACHE_SIZE_AMPLIFY})"
	$restore_text
	echo -n "BENCH_OBJECTS=${BENCH_OBJECTS} BENCH_SIZE=${BENCH_SIZE}"
	echo "(${BENCH_SIZE_AMPLIFY}) BLOCK_SIZE=${BLOCK_SIZE}"
	grn_echo "-------------------------------------------------------"

	for P in ${BENCH_PORTS}; do
		eval "echo "${BENCH_COMMAND}""#"" \
			| fmt -t -w 54 | sed -e 's/$/ \\/g' | sed -e 's/\# \\$//g'
		echo ""
	done
	$shade_text
	eval "echo "${CACHED_COMMAND}""#"" \
		| fmt -t -w 54 | sed -e 's/$/ \\/g' | sed -e 's/\# \\$//g'
	echo ""
	$restore_text
	eval "echo "${STORAGE_COMMAND}""#"" \
		| fmt -t -w 54 | sed -e 's/$/ \\/g' | sed -e 's/\# \\$//g'

	grn_echo "-------------------------------------------------------"
	echo ""
}

# The following two functions manipulate the stdout and stderr.
# They must always be used in pairs.
suppress_output() {
	exec 11>&1
	exec 22>&2
	exec 1>/dev/null 2>/dev/null
}

restore_output() {
	exec 1>&11 11>&-
	exec 2>&22 22>&-
}

nuke_xseg() {
	echo -n "Nuking xseg... "

	# Check before deleting filed files
	if [[ $USE_FILED = "yes" ]] &&
		[[ ( ! "$(basename $PITHOS_FOLDER)" == pithos ||
		! "$(basename $ARCHIP_FOLDER)" == archip ) ]]; then
		red_echo "FAILED!"
		echo ""
		red_echo "There's something wrong with the filed folders"
		red_echo "and you've just dodged a bullet..."
		exit
	fi

	suppress_output

	if [[ $USE_FILED = "yes" ]]; then
		# Delete filed files
		find ${PITHOS_FOLDER} -name "*" -exec rm -rf {} \;
		find ${ARCHIP_FOLDER} -name "*" -exec rm -rf {} \;

		# Re-build filed folders
		mkdir -p ${PITHOS_FOLDER}
		mkdir -p ${ARCHIP_FOLDER}
	fi

	# Clear previous tries
	killall -9 archip-bench
	killall -9 archip-cached
	killall -9 archip-filed
	killall -9 archip-sosd

	# Re-build segment
	eval $XSEG_BIN posix:cached:16:1024:12 destroy create
	for P in $BENCH_PORTS; do
		eval $XSEG_BIN posix:cached: set-next ${P} 1
	done
	restore_output

	grn_echo "DONE!"
}

restore_bench_ports() {
	suppress_output
	for P in $BENCH_PORTS; do
		eval $XSEG_BIN posix:cached: set-next ${P} 0
	done
	restore_output
}

run_background() {
	eval $(eval echo ${1})" &"
}

run_profile_background() {
	run_background "env CPUPROFILE_FREQUENCY=${CPU_SAMPLES} ${1}"
}

read_prompt () {
	while true; do
		read -rn 1 -p "Run this test? [Y]es,[S]kip,[Q]uit: "
		echo ""
		if [[ ( -z $REPLY || $REPLY =~ ^[Yy]$ ) ]]; then
			SKIP=1
			break
		elif [[ $REPLY =~ ^[Ss]$ ]]; then
			SKIP=0
			break
		elif [[ $REPLY =~ ^[Qq]$ ]]; then
			exit
		fi
	done
}
