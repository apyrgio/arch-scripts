#! /bin/bash

##########################
# Script initializations #
##########################

# Find script location
ARCH_SCRIPTS=$(dirname "$(readlink /proc/$$/fd/255)")

#Include helper scripts
source $ARCH_SCRIPTS/init.sh

MAKE="no"
CLEAN="no"
INSTALL="no"
REMOVE="no"

REPO_DIR=/tmp/repo
BUILD_DIR=/tmp/build
VENV_DIR=/home/apyrgio/archipelago-env
ARCH_DIR=/home/apyrgio/archipelago

# Read arguments

if [[ -z $1 ]]; then
	red_echo "No option provided. Aborting..."
	exit
fi

while [[ -n $1 ]]; do
	if [[ $1 = '--clean' ]]; then
		CLEAN="yes"
	elif [[ $1 = '-m' ]]; then
		MAKE="yes"
	elif [[ $1 = '-i' ]]; then
		INSTALL="yes"
	elif [[ $1 = '-r' ]]; then
		REMOVE="yes"
	else
		usage
		red_echo "${1}: Unknown option. Aborting..."
		exit
	fi
	shift
done

if [[ ( $INSTALL = "yes" && $REMOVE = "yes" ) ]]; then
	red_echo "Cannot install and remove packages simultaneously."
	exit
fi

# Enter virtual-env
source $VENV_DIR/bin/activate

if [[ $CLEAN == "yes" ]]; then
	rm -rf ${BUILD_DIR}/*
fi

if [[ $MAKE == "yes" ]]; then
	cd $ARCH_DIR
	devflow-autopkg -b $BUILD_DIR -r $REPO_DIR --no-sign
fi

cd $BUILD_DIR

PACKAGES='libxseg0
	libxseg0-dbg
	python-xseg
	python-archipelago
	archipelago-modules-dkms
	archipelago
	archipelago-dbg
	archipelago-ganeti'

VERSION='_*_amd64'

if [[ $INSTALL == "yes" ]]; then
	DEB_PACKAGES=""
	for pkg in $PACKAGES; do
		pkg=${pkg}${VERSION}".deb"
		if ! ls $pkg &> /dev/null; then
			red_echo "Package \"${pkg}\" is missing. Aborting..."
			exit
		fi
		DEB_PACKAGES=${DEB_PACKAGES}" "${pkg}
	done
	eval dpkg -i $DEB_PACKAGES
elif [[ $REMOVE == "yes" ]]; then
	REV_PACKAGES=""
	for pkg in $PACKAGES; do
		REV_PACKAGES=${pkg}" "${REV_PACKAGES}
	done
	echo "$REV_PACKAGES"
	eval apt-get remove $REV_PACKAGES
fi

# Exit virtual environment
deactivate
