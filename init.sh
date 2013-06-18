#! /bin/bash

##########################
# Function definitions #
##########################

txtrst=$(tput sgr0)					# Reset text color
txtred=$(tput setaf 1)				# Make text red
txtgrn=$(tput setaf 2)				# Make text green
txtbluB=$(tput bold; tput setaf 4)	# Make text green

red_echo() {
	echo -e "${txtred}${1}${txtrst}"
}

grn_echo() {
	echo -e "${txtgrn}${1}${txtrst}"
}

blu_echo() {
	echo -e "${txtbluB}${1}${txtrst}"
}

#ARCH_SCRIPTS must be already set by the caller function
XSEG=$ARCH_SCRIPTS/../archipelago/xseg

