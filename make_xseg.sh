#! /bin/bash

usage() {
	echo "Usage: ./make_xseg.sh [-c] [-d] [-i]"
	echo ""
	echo "Options: -c:  Clean previous tries beforehand"
	echo "         -d:  Print stdout (off by default)"
	echo "         -i:  Install the compiled files"
	echo ""
}

###################
# Initializations #
###################

set -e  #exit on error

# Find script location
ARCH_SCRIPTS=$(dirname "$(readlink /proc/$$/fd/255)")

#Include basic functions
source $ARCH_SCRIPTS/init.sh

PIPE="1>/dev/null"

#############
# Arguments #
#############

while [[ -n $1 ]]; do
	if [[ $1 = '-c' ]]; then CLEAN="yes"
	elif [[ $1 = '-d' ]]; then PIPE=""
	elif [[ $1 = '-i' ]]; then INSTALL="yes"
	elif [[ $1 = '-h' ]]; then usage; exit
	else
		usage
		red_echo "${1}: Unknown command."
		exit
	fi
	shift
done

#############
# Make XSEG #
#############

cd $XSEG

if [[ $CLEAN == "yes" ]]; then
	eval make clean $PIPE
fi
eval make $PIPE
if [[ $INSTALL == "yes" ]]; then
	eval make install $PIPE
fi
