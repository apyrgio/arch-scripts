#! /bin/bash

##########################
# Script initializations #
##########################

# Find script location
ARCH_SCRIPTS=$(dirname "$(readlink /proc/$$/fd/255)")

#Include helper scripts
source $ARCH_SCRIPTS/init.sh
source $ARCH_SCRIPTS/stress_cached_h.sh

##################
# Read arguments #
##################

VERBOSITY=1
BENCH_INSTANCES=1
PROFILE=1
I=0
WAIT=0
BENCH_OP=write
USE_FILED="no"
USE_CACHED="yes"
WARMUP="no"
REPORT="no"
PROG="yes"
RTYPE="req,lat,io"
RPOST='${I_TEST}'

while [[ -n $1 ]]; do
	if [[ $1 = '-l' ]]; then
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
	elif [[ $1 = '-bench' ]]; then
		shift
		BENCH_INSTANCES=$1
	elif [[ $1 = '-seed' ]]; then
		shift
		SEED=$1
	elif [[ $1 = '--filed' ]]; then
		USE_FILED="yes"
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

create_bench_ports

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

BENCH_COMMAND='${BENCH_BIN} -g posix:cached: -p ${P} -tp 0
		-v ${VERBOSITY} --seed ${SEED} -op ${BENCH_OP} --pattern rand
		-ts ${FIN_BENCH_SIZE} -bs ${BLOCK_SIZE} --iodepth ${IODEPTH}
		--ping yes --progress ${PROG} --rtype ${RTYPE}
		--verify no ${RC} -l ${LOG_FOLDER}/${BENCH_LOG} ${RES}'

CACHED_COMMAND='${CACHED_BIN} -g posix:cached: -p 1 -bp 0 -t ${T_CACHED}
		-v ${VERBOSITY} -wcp ${WCP} -n ${NR_OPS}
		-mo ${FIN_CACHE_OBJECTS} -ts ${FIN_CACHE_SIZE}
		-l ${LOG_FOLDER}/cached${I_TEST}.log'

FILED_COMMAND='${FILED_BIN} -g posix:cached: -p 0 -t ${T_FILED}
		-v ${VERBOSITY}
		--pithos ${PITHOS_FOLDER} --archip ${ARCHIP_FOLDER}
		--prefix bench-{$SEED}-
		-l ${LOG_FOLDER}/filed${I_TEST}.log'

SOSD_COMMAND='${SOSD_BIN} -g posix:cached: -p 0 -t ${T_SOSD} -v ${VERBOSITY}
		--pool ${SOSD_POOL}
		-l ${LOG_FOLDER}/sosd${I_TEST}.log'

if [[ $USE_FILED == "yes" ]]; then
	STORAGE_COMMAND=$FILED_COMMAND
	STORAGE="filed"
else
	STORAGE_COMMAND=$SOSD_COMMAND
	STORAGE="sosd"
fi

###########################
# Initialize test options #
###########################

TEST_OPTIONS='WCP CACHE_OBJECTS CACHE_SIZE IODEPTH THREADS
	BENCH_OBJECTS BENCH_SIZE BLOCK_SIZE USE_CACHED'

WCP_VALS="writeback writethrough"
CACHE_OBJECTS_VALS="4 16 64 512"
CACHE_SIZE_VALS="co*2 co*1 co/2"
IODEPTH_VALS="1 16"
THREADS_VALS="single multi"
BENCH_OBJECTS_VALS="bounded holyshit"
BENCH_SIZE_VALS="co/4 co/2 co*1 co*1.5"
BLOCK_SIZE_VALS="4k 8k 32k 128k 256k 1M 4M"
USE_CACHED_VALS="yes no"

# Check if the user has provided his own values for a test option
override_test_options

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
for USE_CACHED in $USE_CACHED_VALS; do

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

	# Make test-specific initializations
	I_TEST=$I
	init_logs ${I_TEST}
	# We eval the following since ${RPOST} may actually point to another
	# variable
	BENCH_LOG=$(eval "echo bench-write${RPOST}.log")
	if [[ $REPORT == "yes" ]]; then
		RES='-res ${REP_FOLDER}/report-${BENCH_LOG}'
	fi
	parse_args $THREADS $CACHE_OBJECTS $CACHE_SIZE \
		$BENCH_SIZE $USE_CACHED
	print_test

	# Determine if we need to wait for user prompt
	if [[ $WAIT == 0 ]]; then
		read_prompt
		if [[ $SKIP == 0 ]]; then continue; fi
	fi

	# Start chosen storage
	run_background "${STORAGE_COMMAND}"
	PID_STORAGE=$!

	# Start cached
	if [[ $USE_CACHED == "yes" ]]; then
		if [[ $PROFILE == 0 ]]; then
			run_profile_background "${CACHED_COMMAND}"
		else
			run_background "${CACHED_COMMAND}"
		fi
		PID_CACHED=$!
	fi
	# Wait a bit to make sure both cached and chosen storage is up
	sleep 1

	# Start bench (warmup mode)
	if [[ ($WARMUP == "yes") ]]; then
		BENCH_LOG=bench-warmup${I_TEST}.log
		BENCH_OP=write
		PID_BENCH=""
		for P in ${BENCH_PORTS}; do
			run_background "${BENCH_COMMAND}"
			PID_BENCH=${PID_BENCH}" $!"
		done
		echo -n "Waiting for bench to finish the warm-up... "
		for PID in ${PID_BENCH}; do
			wait ${PID}
		done
		grn_echo "DONE!"
	fi

	# Start bench (write mode)
	BENCH_LOG=bench-write${I_TEST}.log
	BENCH_OP=write
	PID_BENCH=""
	for P in ${BENCH_PORTS}; do
		run_background "${BENCH_COMMAND}"
		PID_BENCH=${PID_BENCH}" $!"
	done
	echo -n "Waiting for bench to finish writing... "
	for PID in ${PID_BENCH}; do
		wait ${PID}
	done
	grn_echo "DONE!"

	# If we profile cached, we don't want to kill -9 it since the profile
	# data won't be written. We simply send a SIGTERM and wait a second
	# before nuking the segment.
	if [[ $USE_CACHED == "yes" ]] && [[ $PROFILE == 0 ]]; then
		killall archip-cached
		sleep 1
		nuke_xseg
		continue
	fi

	# Start bench (read mode)
	BENCH_LOG=bench-read${I_TEST}.log
	BENCH_OP=read
	PID_BENCH=""
	for P in ${BENCH_PORTS}; do
		run_background "${BENCH_COMMAND}"
		PID_BENCH=${PID_BENCH}" $!"
	done
	echo -n "Waiting for bench to finish reading... "
	for PID in ${PID_BENCH}; do
		wait ${PID}
	done
	grn_echo "DONE!"

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
