#! /bin/bash

##########################
# Function definitions #
##########################

txtrst=$(tput sgr0)			# Reset text color
txtred=$(tput setaf 1)			# Make text red
txtgrn=$(tput setaf 2)			# Make text green
txtgrayB="\033[1;30m"			# Make text bold gray
txtorn="\033[0;33m"			# Make text orange
txtbluB=$(tput bold; tput setaf 4)	# Make text bold blue

red_echo() {
	local prm="-e"
	if [[ $1 == "-n" ]]; then
		prm=$prm" -n"
		shift
	fi

	echo $prm "${txtred}${1}${txtrst}"
}

orn_echo() {
	local prm="-e"
	if [[ $1 == "-n" ]]; then
		prm=$prm" -n"
		shift
	fi

	echo $prm "${txtorn}${1}${txtrst}"
}

grn_echo() {
	local prm="-e"
	if [[ $1 == "-n" ]]; then
		prm=$prm" -n"
		shift
	fi

	echo $prm "${txtgrn}${1}${txtrst}"
}

blu_echo() {
	local prm="-e"
	if [[ $1 == "-n" ]]; then
		prm=$prm" -n"
		shift
	fi

	echo $prm "${txtbluB}${1}${txtrst}"
}

gray_echo() {
	local prm="-e"
	if [[ $1 == "-n" ]]; then
		prm=$prm" -n"
		shift
	fi

	echo $prm "${txtgrayB}${1}${txtrst}"
}

shade_text() {
	echo -e -n "${txtgrayB}"
}

restore_text() {
	echo -e -n "${txtrst}"
}


#ARCH_SCRIPTS must be already set by the caller function
#XSEG=$ARCH_SCRIPTS/../archipelago/xseg
XSEG=${HOME}/archipelago/xseg

