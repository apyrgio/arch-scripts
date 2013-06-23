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
USE_PFILED="no"
USE_CACHED="yes"

# Remember, in Bash 0 is true and 1 is false
while [[ -n $1 ]]; do
	if [[ $1 = '-ff' ]]; then
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
	elif [[ $1 = '--pfiled' ]]; then
		USE_PFILED="yes"
	elif [[ $1 = '-v' ]]; then
		shift
		VERBOSITY=$1
	elif [[ $1 = '-p' ]]; then
		PROFILE=0
		shift
		CPU_SAMPLES=$1
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
		-ts ${BENCH_SIZE} --progress yes --iodepth ${IODEPTH}
		--verify meta ${RC} -l ${LOG_FOLDER}/bench${I}.log'

CACHED_COMMAND='${CACHED_BIN} -g posix:cached: -p 1 -bp 0 -t ${T_CACHED}
		-v ${VERBOSITY} -wcp ${WCP} -n ${NR_OPS} -mo ${CACHE_OBJECTS}
		-ts ${CACHE_SIZE}
		-l ${LOG_FOLDER}/cached${I}.log'

PFILED_COMMAND='${PFILED_BIN} -g posix:cached: -p 0 -t ${T_PFILED} -v ${VERBOSITY}
		--pithos ${PITHOS_FOLDER} --archip ${ARCHIP_FOLDER}
		-l ${LOG_FOLDER}/pfiled${I}.log'

SOSD_COMMAND='${SOSD_BIN} -g posix:cached: -p 0 -t ${T_SOSD} -v ${VERBOSITY}
		--pool ${SOSD_POOL}
		-l ${LOG_FOLDER}/sosd${I}.log'

if [[ $USE_PFILED == "yes" ]]; then
	STORAGE_COMMAND=$PFILED_COMMAND
	STORAGE="pfiled"
else
	STORAGE_COMMAND=$SOSD_COMMAND
	STORAGE="sosd"
fi

#############
# Main loop #
#############

for WCP in writeback writethrough; do			# +512
for CACHE_OBJECTS in 4 16 64 512; do			# +128
for CACHE_SIZE_AMPLIFY in 2x 1.5x 1x 0.5x; do		# +32
for IODEPTH in 1 16; do					# +16
for THREADS in single multi; do				# +8
for BENCH_OBJECTS in bounded holyshit; do		# +4
for BENCH_SIZE_AMPLIFY in 0.25x 0.5x 1x 1.5x; do	# +1
for USE_CACHED in yes no; do

	# A new test is considered to begin only when cached is used.
	# Else, it's just the second part of the test.
	if [[ $USE_CACHED == "yes" ]]; then
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

		if [[ $CACHE_SIZE_AMPLIFY == '1.5x' ]]; then continue; fi

		I_TEST=${I}"a"
	else
		restore_next_ports
		I_TEST=${I}"b"
	fi

	# Make test-specific initializations
	init_logs ${I_TEST}
	parse_args $THREADS $CACHE_SIZE_AMPLIFY $BENCH_SIZE_AMPLIFY $BENCH_OBJECTS
	print_test

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

	# Start bench (write mode)
	BENCH_OP=write
	for P in ${BENCH_PORTS}; do
		run_background "${BENCH_COMMAND}"
		PID_BENCH=${PID_BENCH}" $!"
	done
	echo -n "Waiting for bench to finish writing... "
	for PID in ${PID_BENCH}; do
		wait ${PID}
	done
	grn_echo "DONE!"

	if [[ $USE_CACHED == "yes" ]] && [[ $PROFILE == 0 ]]; then
		killall archip-cached
		sleep 1
		nuke_xseg
		continue
	fi

	# Start bench (read mode)
	BENCH_OP=read
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
