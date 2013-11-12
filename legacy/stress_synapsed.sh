#! /bin/bash

##########################
# Script initializations #
##########################

# Find script location
ARCH_SCRIPTS=$(dirname "$(readlink /proc/$$/fd/255)")

#Include helper scripts
source $ARCH_SCRIPTS/init.sh
source $ARCH_SCRIPTS/stress_synapsed_h.sh

##################
# Read arguments #
##################

VERBOSITY=1
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

############################
# Clean all previous tries #
############################

# Call nuke_xseg to clear the segment and kill all peer processes
nuke_xseg

if [[ $CLEAN ]]; then exit; fi

##############################
# Create arguments for peers #
##############################

create_seed $SEED

BENCH_COMMAND='bench -g posix:host: -p 3 -tp 2 -v ${VERBOSITY}
			-op ${BENCH_OP} --seed ${SEED} --pattern rand
			-ts ${BENCH_SIZE} -bs ${BENCH_BLOCK} --progress yes
			--iodepth ${IODEPTH} --verify meta --insanity eccentric
			-l /var/log/stress_synapsed/bench${I}.log'

SYNAPSED_H_COMMAND='synapsed -g posix:host: -p 2 -v ${VERBOSITY}
			-ra 192.168.0.1 -txp 3 -hp 1134 -rp 3704
			-l /var/log/stress_synapsed/synapsed-host${I}.log'

SYNAPSED_R_COMMAND='synapsed -g posix:remote: -p 1 -v ${VERBOSITY}
			-ra 192.168.0.1 -txp 0 -rp 1134 -hp 3704
			-l /var/log/stress_synapsed/synapsed-remote${I}.log'

MT_PFILED_COMMAND='mt-pfiled -g posix:remote: -p 0 -t 64 -n 64 -v ${VERBOSITY}
			--pithos /tmp/pithos1/ --archip /tmp/pithos2/
			-l /var/log/stress_synapsed/mt-pfiled${I}.log'

#############
# Main loop #
#############

#set -e  #exit on error
for IODEPTH in 1 16; do
	for BENCH_BLOCK in 4K 32K 256K; do
		for BENCH_SIZE in x1 x32 x1024; do
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
			init_log synapsed-host${I}.log
			init_log synapsed-remote${I}.log
			init_log mt-pfiled${I}.log

			parse_args $BENCH_SIZE
			print_test

			if [[ $WAIT == 0 ]]; then
				read_prompt
				if [[ $SKIP == 0 ]]; then continue; fi
			fi

			# Start mt-pfiled
			eval ${MT_PFILED_COMMAND}" &"
			PID_MTPF=$!

			# Start synapsed (host)
			eval ${SYNAPSED_H_COMMAND}" &"
			PID_SYNAPSED_H=$!

			# Start synapsed (remote)
			eval ${SYNAPSED_R_COMMAND}" &"
			PID_SYNAPSED_R=$!

			# Wait a bit to make sure both synapsed and mt-pfiled is up
			sleep 1

			# Start bench (write mode)
			BENCH_OP=write
			eval ${BENCH_COMMAND}" &"
			PID_BENCH=$!

			echo -n "Waiting for bench to finish writing... "
			wait ${PID_BENCH}
			grn_echo "DONE!"

			# Start bench (read mode)
			BENCH_OP=read
			eval ${BENCH_COMMAND}" &"
			PID_BENCH=$!

			echo -n "Waiting for bench to finish reading... "
			wait ${PID_BENCH}
			grn_echo "DONE!"

			nuke_xseg
		done
	done
done
