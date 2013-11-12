#! /bin/bash

##########################
# Script initializations #
##########################

# Find script location
ARCH_SCRIPTS=$(dirname "$(readlink /proc/$$/fd/255)")

#Include helper scripts
source $ARCH_SCRIPTS/init.sh
source $ARCH_SCRIPTS/stress_xseg_h.sh

##################
# Read arguments #
##################

SEGMENT="posix:stress:16:1024:12"
VERBOSITY=1
BENCH_INSTANCES=1
PROFILE=1
I=0
WAIT=0
BENCH_OP=write
WARMUP="no"
REPORT="no"
PROG="yes"
RTYPE="req,lat,io"
STYPE="no"
RPOST='${I_TEST}'
VERIFY="meta"
BE_GENTLE="hellno"
RESTART_CACHED="no"
TOPOLOGY_VALS="bench->cached->sosd"
RADDR=$( hostname -f )

while [[ -n $1 ]]; do
	if [[ $1 = '-g' ]]; then
		shift
		SEGMENT=$1
	elif [[ $1 = '-l' ]]; then
		shift
		if ! is_path_safe $1; then
			red_echo "-l ${1}: Log path is unsafe"
			exit
		fi
		LOG_FOLDER=$1
	elif [[ $1 = '-r' ]]; then
		REPORT="yes"
		shift
		if ! is_path_safe $1; then
			red_echo "-r ${1}: Report path is unsafe"
			exit
		fi
		REP_FOLDER=$1
	elif [[ $1 = '-ra' ]]; then
		shift
		RADDR=$1
	elif [[ $1 = '-prog' ]]; then
		shift
		PROG=$1
	elif [[ $1 = '-rtype' ]]; then
		shift
		RTYPE=$1
	elif [[ $1 = '-rpost' ]]; then
		shift
		RPOST=$1
	elif [[ $1 = '-ff' ]]; then
		shift
		FF=0
		FLIMIT=$1
	elif [[ $1 = '-test' ]]; then
		shift
		TEST=0
		TLIMIT=$1
	elif [[ $1 = '-until' ]]; then
		shift
		UNTIL=0
		ULIMIT=$1
	elif [[ $1 = '-verify' ]]; then
		shift
		VERIFY=$1
	elif [[ $1 = '-seed' ]]; then
		shift
		SEED=$1
	elif [[ $1 = '--gentle' ]]; then
		BE_GENTLE="yes"
	elif [[ $1 = '--restart' ]]; then
		RESTART_CACHED="yes"
	elif [[ $1 = '-v' ]]; then
		shift
		VERBOSITY=$1
	elif [[ $1 = '-p' ]]; then
		PROFILE=0
		shift
		CPU_SAMPLES=$1
	elif [[ $1 = '-w' ]]; then
		WARMUP="yes"
	elif [[ $1 = '-y' ]]; then
		WAIT=1
	elif [[ $1 = '-c' ]]; then
		CLEAN=0
	elif [[ $1 = '-h' ]]; then
		usage
		exit
	else
		usage
		red_echo "${1}: Unknown option. Aborting..."
		exit
	fi
	shift
done

# Validation of argument sanity

if [[ (-n ${TEST}) && ((-n $FF || -n $UNTIL)) ]]; then
	red_echo "-test can't be used in conjuction with -ff or -until"
	exit
fi

if [[ -n $FF && -n $UNTIL && $FLIMIT -gt $ULIMIT ]]; then
	red_echo "Test range makes no sense: [${FLIMIT},${ULIMIT}]"
	exit
fi

########################
# Initialize topology #
########################

create_topology

############################
# Clean all previous tries #
############################

#Initialize the needed files
init_binaries_and_folders

# Call nuke_xseg to clear the segment and kill all peer processes
nuke_xseg

if [[ $CLEAN ]]; then exit; fi

##############################
# Create arguments for peers #
##############################

create_seed $SEED

BENCH_COMMAND='${BENCH_BIN} -g ${SEGMENT}: -p ${BENCH_PORT}
		-tp ${BENCH_TARGET} -v ${VERBOSITY}
		--seed ${SEED} -op ${BENCH_OP} --pattern rand
		-ts ${FIN_BENCH_SIZE} -bs ${BLOCK_SIZE} --iodepth ${IODEPTH}
		--ping yes --progress ${PROG} --rtype ${RTYPE}
		--verify $VERIFY ${RC} ${RES} -l ${LOG_FOLDER}/${BENCH_LOG}'

CACHED_COMMAND='${CACHED_BIN} -g ${SEGMENT}: -p ${CACHED_PORT}
		-bp ${CACHED_TARGET} -t ${T_CACHED}
		-v ${VERBOSITY} -wcp ${WCP} -n ${NR_OPS}
		-mo ${FIN_CACHE_OBJECTS} -ts ${FIN_CACHE_SIZE}
		--dirty_threshold 75
		-l ${LOG_FOLDER}/cached${I_TEST}.log'

FILED_COMMAND='${FILED_BIN} -g ${SEGMENT}: -p ${FILED_PORT}
		-t ${T_FILED} -v ${VERBOSITY}
		--pithos ${PITHOS_FOLDER} --archip ${ARCHIP_FOLDER}
		--prefix bench-${SEED}-
		-l ${LOG_FOLDER}/filed${I_TEST}.log'

SOSD_COMMAND='${SOSD_BIN} -g ${SEGMENT}: -p ${SOSD_PORT}
		-t ${T_SOSD} -v ${VERBOSITY}
		--pool ${SOSD_POOL}
		-l ${LOG_FOLDER}/sosd${I_TEST}.log'

SYNAPSED_C_COMMAND='${SYNAPSED_BIN} -g ${SEGMENT}: -p ${SYNAPSED_C_PORT}
		-v ${VERBOSITY} -ra ${RADDR} -txp ${SYNAPSED_C_TARGET}
		-hp 1134 -rp 3704
		-l ${LOG_FOLDER}/synapsed-client${I_TEST}.log'

SYNAPSED_S_COMMAND='${SYNAPSED_BIN} -g ${SEGMENT}: -p ${SYNAPSED_S_PORT}
		-v ${VERBOSITY} -ra ${RADDR} -txp ${SYNAPSED_S_TARGET}
		-rp 1134 -hp 3704
		-l ${LOG_FOLDER}/synapsed-server${I_TEST}.log'

###########################
# Initialize test options #
###########################

TEST_OPTIONS='WCP CACHE_OBJECTS CACHE_SIZE IODEPTH THREADS
	BENCH_OBJECTS BENCH_SIZE BLOCK_SIZE TOPOLOGY'

WCP_VALS="writeback writethrough"
CACHE_OBJECTS_VALS="4 16 64 512"
CACHE_SIZE_VALS="co*2 co*1 co/2"
IODEPTH_VALS="1 16"
THREADS_VALS="1 2 4"
BENCH_OBJECTS_VALS="bounded holyshit"
BENCH_SIZE_VALS="co/4 co/2 co*1 co*1.5"
BLOCK_SIZE_VALS="4k 8k 32k 128k 256k 1M 4M"
TOPOLOGY_VALS="bench->cached->sosd synapsed_s->filed"

# Check if the user has provided his own values for a test option
override_test_options

##############
# Bench logs #
##############

BENCH_LOG='bench-${BENCH_LOG_OP}${I_TEST}.log'
if [[ $REPORT == "yes" ]]; then
	BENCH_REPORT='report-bench-${BENCH_LOG_OP}${RPOST}.log'
	RES="-res ${REP_FOLDER}/${BENCH_REPORT}"
fi

#############
# Main loop #
#############

for WCP in $WCP_VALS; do
for CACHE_OBJECTS in $CACHE_OBJECTS_VALS; do
for CACHE_SIZE in $CACHE_SIZE_VALS; do
for IODEPTH in $IODEPTH_VALS; do
for THREADS in $THREADS_VALS; do
for BENCH_OBJECTS in $BENCH_OBJECTS_VALS; do
for BENCH_SIZE in $BENCH_SIZE_VALS; do
for BLOCK_SIZE in $BLOCK_SIZE_VALS; do
for TOPOLOGY in $TOPOLOGY_VALS; do

	I=$(( $I+1 ))

	# Check if user has asked to fast-forward or run a specific test
	if [[ ($UNTIL && $I -gt $ULIMIT) ]]; then exit
	elif [[ $TEST ]]; then
		if [[ $I -lt $TLIMIT ]]; then continue
		elif [[ $I -gt $TLIMIT ]]; then exit
		fi
	elif [[ $FF ]]; then
		if [[ $I -lt $FLIMIT ]]; then continue
		elif [[ $I -eq $FLIMIT ]]; then FF=1
		fi
	fi

	create_topology $TOPOLOGY

	# Make test-specific initializations
	I_TEST=$I
	init_logs ${I_TEST}
	BENCH_LOG_OP=write
	parse_args $THREADS $CACHE_OBJECTS $CACHE_SIZE \
		$BENCH_SIZE $USE_CACHED
	print_test

	# Determine if we need to wait for user prompt
	if [[ $WAIT == 0 ]]; then
		read_prompt
		if [[ $SKIP == 0 ]]; then continue; fi
	fi

	# FIXME: Shorten this
	if [[ $USE_FILED == "yes" ]]; then
		run_background "${FILED_COMMAND}"
	fi

	if [[ $USE_SOSD == "yes" ]]; then
		run_background "${SOSD_COMMAND}"
	fi

	if [[ $USE_SYNAPSED_S == "yes" ]]; then
		run_background "${SYNAPSED_S_COMMAND}"
	fi

	if [[ $USE_SYNAPSED_C == "yes" ]]; then
		run_background "${SYNAPSED_C_COMMAND}"
	fi

	# Start cached
	if [[ $USE_CACHED == "yes" ]]; then
		if [[ $PROFILE == 0 ]]; then
			run_profile_background "${CACHED_COMMAND}"
		else
			run_background "${CACHED_COMMAND}"
		fi
		PID_CACHED=$!
	fi

	# Wait a bit to make sure both cached and chosen blocker is up
	sleep 1

	# Start bench (warmup mode)
	if [[ $USE_BENCH == "yes" ]] &&
		[[ ($WARMUP == "yes") ]]; then
		BENCH_LOG_OP=warmup
		BENCH_OP=write

		run_background "${BENCH_COMMAND}"
		PID_BENCH=$!

		echo -n "Waiting for bench to finish the warm-up... "
		wait ${PID_BENCH}

		grn_echo "DONE!"
	fi

	# Start bench (write mode)
	if [[ $USE_BENCH == "yes" ]]; then
		BENCH_LOG_OP=write
		BENCH_OP=write

		run_background "${BENCH_COMMAND}"
		PID_BENCH=$!

		echo -n "Waiting for bench to finish writing... "
		wait ${PID_BENCH}

		grn_echo "DONE!"
	fi

	# If we profile cached, we don't want to kill -9 it since the profile
	# data won't be written. We simply send a SIGTERM and wait a second
	# before nuking the segment.
	if [[ $USE_CACHED == "yes" ]] && [[ $PROFILE == 0 ]]; then
		killall archip-cached
		sleep 1
		nuke_xseg
		continue
	fi

	# (Optional) Restart cached
	if [[ $RESTART_CACHED == "yes" ]] &&
		[[ $USE_CACHED == "yes" ]]; then
		echo -n "Restarting cached... "
		killall archip-cached
		wait $PID_CACHED
		EXIT_CODE=$?

		# Throw error if failed
		if [[ $EXIT_CODE -gt 0 ]]; then
			red_echo "FAILED (error: $EXIT_CODE)"
			exit
		fi

		run_background "${CACHED_COMMAND}"
		PID_CACHED=$!
		grn_echo "DONE!"
		sleep 1
	fi

	if [[ $USE_BENCH == "yes" ]]; then
		# Start bench (read mode)
		BENCH_LOG_OP=read
		BENCH_OP=read

		run_background "${BENCH_COMMAND}"
		PID_BENCH=$!

		echo -n "Waiting for bench to finish reading... "
		for PID in ${PID_BENCH}; do
			wait ${PID}
		done
		grn_echo "DONE!"
	fi

	# Wait for cached to exit normally, before nuking the segment
	if [[ $BE_GENTLE == "yes" ]] &&
		[[ $USE_CACHED == "yes" ]]; then
		killall archip-cached
		wait $PID_CACHED
	fi

	# Since cached's termination has not been solved yet, we
	# have to resort to weapons of mass destruction
	nuke_xseg
done
done
done
done
done
done
done
done
done
