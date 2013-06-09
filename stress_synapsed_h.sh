#! /bin/bash

#####################
# Haelper functions #
#####################

usage() {
	echo "Usage: ./stress_synapsed [-test <i>] [-ff <i>] [-until <i>]"
	echo "                         [-seed <n>] [-v <i>] [-y] [-c] [-h]"
	echo ""
	echo "Options: -test <i>:  run only test <i>"
	echo "         -ff <i>:    fast-forward to test <i>, run every test from "
	echo "                     there on"
	echo "         -until <i>: run every test until AND test <i>"
	echo "         -seed <n>:  use <n> as a seed for the test (9-digits only)"
	echo "         -v <l>:     set verbosity level to <l>"
	echo "         -y:         do not wait between tests"
	echo "         -c:         just clean the segment"
	echo "         -h:         rint this message"
	echo ""
	echo "---------------------------------------------------------------------"
	echo "Additional info:"
	echo ""
	echo "* None of the above options needs to be used. By default,"
	echo "  stress_synapsed will iterate the list of tests and pause between "
	echo "  each one so that the user can take a look at the logs."
	echo ""
	echo "* If the user has not given a seed, stress_synapsed will pick a "
	echo "  random seed value."
	echo ""
	echo "* The -ff and -until options can be used together to run tests"
	echo "  within a range."
	echo ""
	echo "* The bench instances will all do the same job. The difference is"
	echo "  that they will wait in a different port."
	echo ""
	echo "* An easy way to check out the output would be to start 3 terminals"
	echo "  and simply have them do: tail -F /var/log/bench* (or bench*,"
	echo "  synapsed_host*, synapsed_remote*, mt-pfiled*). Thus, when a file is"
	echo "  rm'ed or a new file with the same"
	echo "  prefix has been added, tail will read it and you won't have to do"
	echo "  anything."
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

parse_args() {
	# ${1} is for benchmark size
	if [[ ${1} = 'x1' ]]; then
		BENCH_SIZE=${BENCH_BLOCK}
	elif [[ ${1} = 'x4' ]]; then
		BENCH_SIZE=$(( 4 * ${BENCH_BLOCK%K} ))'K'
	elif [[ ${1} = 'x32' ]]; then
		BENCH_SIZE=$(( 32 * ${BENCH_BLOCK%K} ))'K'
	elif [[ ${1} = 'x1024' ]]; then
		BENCH_SIZE=${BENCH_BLOCK/K/M}
	else
		red_echo "${1} is not a valid bench size option"
		exit
	fi
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
	echo ""
	grn_echo "Summary of Test ${I}:"
	echo "IODEPTH=${IODEPTH} TOTAL_SIZE=${BENCH_SIZE} BLOCK_SIZE=${BENCH_BLOCK}"
	grn_echo "-----------------------------------------------------------------"

	eval "echo "${BENCH_COMMAND}""#"" \
		| fmt -t -w 72 | sed -e 's/$/ \\/g' | sed -e 's/\# \\$//g'
	echo ""
	eval "echo "${SYNAPSED_H_COMMAND}""#"" \
		| fmt -t -w 72 | sed -e 's/$/ \\/g' | sed -e 's/\# \\$//g'
	echo ""
	eval "echo "${SYNAPSED_R_COMMAND}""#"" \
		| fmt -t -w 72 | sed -e 's/$/ \\/g' | sed -e 's/\# \\$//g'
	echo ""
	eval "echo "${MT_PFILED_COMMAND}""#"" \
		| fmt -t -w 72 | sed -e 's/$/ \\/g' | sed -e 's/\# \\$//g'

	grn_echo "-----------------------------------------------------------------"
	echo ""
}

init_log() {
	LOG=/var/log/stress_synapsed/${1}

	# Truncate previous logs
	cat /dev/null > $LOG

	echo "" >> $LOG
	blu_echo "******************" >> $LOG
	blu_echo " TEST ${I} STARTED" >> $LOG
	blu_echo "******************" >> $LOG
	echo "" >> $LOG
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
	suppress_output

	# Delete mt-pfiled files
	find /tmp/pithos1/ -name "*" -exec rm -rf {} \;
	find /tmp/pithos2/ -name "*" -exec rm -rf {} \;
	mkdir /tmp/pithos1/ /tmp/pithos2/

	# Clear previous tries
	killall -9 bench
	killall -9 synapsed
	killall -9 mt-pfiled

	# Re-build segment
	xseg posix:host:16:1024:12 destroy create
	xseg posix:remote:16:1024:12 destroy create

	restore_output
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
