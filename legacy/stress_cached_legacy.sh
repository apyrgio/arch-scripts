#! /bin/bash

##########################
# Script initializations #
##########################

# Find script location
ARCH_SCRIPTS=$(dirname "$(readlink /proc/$$/fd/255)")

#Include helper scripts
source $ARCH_SCRIPTS/init.sh
source $ARCH_SCRIPTS/stress_cached_legacy_h.sh

##################
# Read arguments #
##################

VERBOSITY=1
BENCH_INSTANCES=1
I=0
WAIT=0
BENCH_OP=write

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
	elif [[ $1 = '-v' ]]; then
		shift
		VERBOSITY=$1
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
	-ts ${BENCH_SIZE} --progress yes --iodepth ${IODEPTH} --verify meta
	-l ${LOG_FOLDER}/bench${I}.log'

CACHED_COMMAND='${CACHED_BIN} -g posix:cached: -p 1 -bp 0 -t ${T_CACHED}
	-v ${VERBOSITY} -wcp ${WCP} -n ${NR_OPS} -cs ${CACHE_SIZE}
	-l ${LOG_FOLDER}/cached${I}.log'

PFILED_COMMAND='${PFILED_BIN} -g posix:cached: -p 0 -t ${T_MTPF} -v ${VERBOSITY}
	--pithos ${PITHOS_FOLDER} --archip ${ARCHIP_FOLDER}
	-l ${LOG_FOLDER}/pfiled${I}.log'

#############
# Main loop #
#############

#set -e  #exit on error
for CACHE_SIZE in 4 16 64 512; do
for WCP in writeback writethrough; do
for IODEPTH in 1 16; do
for THREADS in single multi; do
for BENCH_SIZE in '1/2' '1+1/2' '2+1/2'; do
	# Check if user has asked to fast-forward or run a specific
	# test
	I=$(( $I+1 ))

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
	init_log bench${I}.log
	init_log cached${I}.log
	init_log pfiled${I}.log

	parse_args $THREADS $BENCH_SIZE $CACHE_SIZE
	print_test

	if [[ $WAIT == 0 ]]; then
		read_prompt
		if [[ $SKIP == 0 ]]; then continue; fi
	fi

	# Start pfiled
	run_background "${PFILED_COMMAND}"
	PID_PFILED=$!

	# Start cached
	run_background "${CACHED_COMMAND}"
	PID_CACHED=$!
	# Wait a bit to make sure both cached and pfiled is up
	sleep 11

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

	if [[ $PROFILE == 0 ]]; then
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
