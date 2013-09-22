#! /bin/bash

PEERS="bench cached filed sosd synapsed_c synapsed_s"

#####################
# Helper functions #
#####################

usage() {
	echo "Usage: ./stress_cached [-l <path>] [-r <path>]"
	echo "                       [-prog <p>] [-rtype <t>]"
	echo "                       [-test <i>] [-ff <i>] [-until <i>]"
	echo "                       [-bench <p>] [-seed <n>]"
	echo "                       [-v <i>] [-p <n>] [-y] [-c] [-h]"
	echo ""
	echo "Options: -l <path>:  store logs in this path"
	echo "                     default: ${ARCH_SCRIPTS}/log/stress_cached"
	echo "                     permitted: ${HOME}/* or /tmp/*"
	echo "         -r <path>:  activate bench reports and store them in "
	echo "                     this path"
	echo "         -ra <addr>: remote address of synapsed"
	echo "         -prog <p>:  choose progress type"
	echo "         -rtype <t>: choose report type"
	echo "         -stype <t>: choose synapsed type [client|sever]"
	echo "         -rpost <p>: use this postfix for reports before '.log'"
	echo "         -test <i>:  run only test <i>"
	echo "         -ff <i>:    fast-forward to test <i>, run every test"
	echo "                     from there on"
	echo "         -until <i>: run every test until AND test <i>"
	echo "         -verify <m>:set verification mode <m> for bench"
	echo "         -bench <p>: define number of bench instances"
	echo "         -seed <n>:  use <n> as a seed for the test (9-digits"
	echo "                     only)"
	echo "         --filed:    use filed instead of sosd for blocker"
	echo "         --gentle:   wait for cached to exit before nuking xseg"
	echo "         --restart:  restart cached before reading from it"
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
	echo "  with the same prefix has been added, tail will read it and you won't"
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



is_path_safe() {
	if [[ ! $1 == ${HOME}* ]] &&
		[[ ! $1 == "/tmp"* ]]; then
		return 1
	fi
	return 0
}

# Both functions expect a word of phrase and they echo it back in
# lowercase or uppercase
to_uppercase() {
	echo $@ | tr '[a-z]' '[A-Z]'
}

to_lowercase() {
	echo $@ | tr '[A-Z]' '[a-z]'
}

# Expects a peer name($1) and a yes or no ($2)
use_peer() {
	local peer
	local peer_use

	peer=$( to_uppercase $1 )
	peer_use="USE_${peer}"
	eval ${peer_use}=$2
}

# FIXME: The below will not work with a multi-bench test
init_topology() {
	local peer
	local use_peer

	for peer in $PEERS; do
		use_peer $peer no
	done

	BENCH_PORT=2
	CACHED_PORT=1
	SOSD_PORT=0
	FILED_PORT=10
	SYNAPSED_C_PORT=9
	SYNAPSED_S_PORT=6
}

create_topology() {
	local peer
	local topology
	local target
	local target_var
	local target_port
	local i=0
	local next
	local prev

	init_topology

	topology=$( echo ${TOPOLOGY_VALS} | sed 's/->/\ /g' )

	for peer in $topology; do
		i=$(( $i + 1 ))
		prev=$(( $i - 1 ))
		next=$(( $i + 1 ))

		use_peer $peer yes

		if [[ $peer == "filed" || $peer == "sosd" ]]; then
			return
		elif [[ $peer == "synapsed_c" ]]; then
			target=$(echo ${topology} | cut -d " " -f ${prev})
		else
			target=$(echo ${topology} | cut -d " " -f ${next})
		fi

		peer=$( to_uppercase $peer )
		target=$( to_uppercase $target )
		target_var="${peer}_TARGET"
		target_port="${target}_PORT"
		eval ${target_var}=${!target_port}
	done
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
	SYNAPSED_BIN="${LD_PRELOAD_PATH} ${XSEG}/peers/user/archip-synapsed"

	# Create necessary folders
	mkdir -p ${LOG_FOLDER}
	if [[ -n ${REP_FOLDER} ]]; then
		mkdir -p ${REP_FOLDER}
	fi
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

	for peer in bench-warmup bench-write bench-read \
		cached sosd filed synapsed-client synapsed-server; do
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
	if [[ ${1} -gt 0 ]]; then
		T_SOSD=1
		T_FILED=64
		T_CACHED=${1}
	else
		red_echo "${1} is not a valid thread option"
		exit
	fi

	# ${2}, ${3}, ${4} are the cache objects (co), cache size (cs) and
	# bench size (bs) arguments respectively. These, along with the object
	# size and block size, must be passed to calc_sizes.py in order to be
	# processed and to resolve the dependencies between them (see more in
	# the help in calc_sizes.py).

	if [[ ${BENCH_OBJECTS} == "holyshit" ]]; then
		local rc="rc"
	fi

	ORIG_CACHE_OBJECTS=$2
	ORIG_CACHE_SIZE=$3
	ORIG_BENCH_SIZE=$4

	ARG_SIZES=$(python ${ARCH_SCRIPTS}/calc_sizes.py \
		4M ${BLOCK_SIZE} ${2} ${3} ${4} ${rc})
	FIN_CACHE_OBJECTS=$(echo ${ARG_SIZES} | cut -d " " -f 1)
	FIN_CACHE_SIZE=$(echo ${ARG_SIZES} | cut -d " " -f 2)
	FIN_BENCH_SIZE=$(echo ${ARG_SIZES} | cut -d " " -f 3)

	if [[ ${BENCH_OBJECTS} == "holyshit" ]]; then
		RC="-rc ${FIN_BENCH_SIZE}"
		FIN_BENCH_SIZE="999G"
	else
		RC=""
	fi

	if [[ ${FIN_CACHE_OBJECTS} -lt 16 ]] 2>/dev/null ; then
		NR_OPS=${FIN_CACHE_OBJECTS}
	else
		NR_OPS=16
	fi

	# ${5} shows if cached is used in this test.
	# If cached is not used, unset "next" ports for bench, so that requests
	# can go directly to blocker.
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
print_command() {
	eval "echo "$(eval "echo "$(eval "echo "${1}""#"")) \
		| fmt -t -w 54 | sed -e 's/$/ \\/g' | sed -e 's/\# \\$//g'
}

print_test() {
	local peer
	local peer_command
	local peer_use

	echo ""
	grn_echo "Summary of Test ${I_TEST} (SEED ${SEED}):"

	if [[ $USE_BENCH == "yes" ]]; then
		echo -n "BENCH_OBJECTS=${BENCH_OBJECTS} "
		echo -n "BENCH_SIZE=${FIN_BENCH_SIZE}(${ORIG_BENCH_SIZE}) "
		echo "BLOCK_SIZE=${BLOCK_SIZE}"
		echo "IODEPTH=${IODEPTH}"
	fi

	if [[ $USE_CACHED == "yes" ]]; then
		echo -n "CACHE_OBJECTS=${FIN_CACHE_OBJECTS}($ORIG_CACHE_OBJECTS) "
		echo "CACHE_SIZE=${FIN_CACHE_SIZE}(${ORIG_CACHE_SIZE})"
		echo "WCP=${WCP} THREADS=${THREADS}"
	fi

	grn_echo -n "-------------------------------------------------------"
	for peer in $PEERS; do
		peer=$( to_uppercase $peer )

		peer_use="USE_${peer}"
		if [[ ${!peer_use} == no ]]; then continue; fi

		peer_command="${peer}_COMMAND"
		echo ""
		print_command "${!peer_command}"
	done
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
	killall -9 archip-synapsed

	# Re-build segment
	eval $XSEG_BIN posix:cached:16:1024:12 destroy create
	for P in $BENCH_PORTS; do
		eval $XSEG_BIN posix:cached: set-next ${P} ${BENCH_TARGET_PORT}
	done
	restore_output

	grn_echo "DONE!"
}

restore_bench_ports() {
	suppress_output
	for P in $BENCH_PORTS; do
		eval $XSEG_BIN posix:cached: set-next ${P} ${BENCH_TARGET_PORT}
	done
	restore_output
}

run_background() {
	eval $(eval "echo "$(eval "echo "${1}))" &"
}

run_profile_background() {
	run_background "env CPUPROFILE_FREQUENCY=${CPU_SAMPLES} ${1}"
}

read_prompt () {
	while true; do
		read -rn 1 -p "Run this test? [Y]es (default), [S]kip, [Q]uit: "
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
