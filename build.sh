#!/bin/bash

# ----------------------------------------------------------
# base setup

true ${TOP:=$(pwd)}
true ${OUT:=/tmp/wireless-modules}
true ${ANDROID:=y}

# default config
KDIR=/opt/FriendlyARM/nanopi3/linux-3.4.y
BCFG=nanopi3
MAKE="make -j8"

# ----------------------------------------------------------
# local functions

SELF=$0

function usage()
{
	echo "Usage: $0 [ARGS]"
	echo ""
	echo "Options:"
	echo "  -k <kernel dir>       default: $KDIR"
	echo "  -c <backports config> default: $BCFG"
	echo "  -o <install to>       default: $OUT"
	echo ""
	echo "  -p                    strip .ko and create package"
	echo "  -h                    show this help message and exit"
	echo "  clean                 clean all"
}

function parse_args()
{
	TEMP=`getopt -o "c:k:o:ph" -n "$SELF" -- "$@"`
	if [ $? != 0 ] ; then exit 1; fi
	eval set -- "$TEMP"

	while true; do
		case "$1" in
			-k ) KDIR=$2; shift 2;;
			-c ) BCFG=$2; shift 2;;
			-o ) OUT=$2; shift 2;;
			-p ) PKG=wireless-modules.tgz; shift ;;
			-h ) usage; exit 1 ;;
			-- ) shift; break ;;
			*  ) echo "invalid option $1"; usage; return 1 ;;
		esac
	done
	if [ "x${1,,}" = "xclean" ]; then
		TARGET=clean
	fi
}

function FA_RunCmd() {
	[ "$V" = "1" ] && echo "+ ${@}"
	eval $@ || exit $?
}

function check_kernel_dir()
{
	if [ ! -d "$1" ]; then
		echo "Couldn't find kernel source: $1"
		exit -1
	fi
}

function change_work_dir()
{
	if [ ! -d "$1" ]; then
		echo "Error: \`$1': No such directory"
		exit -1
	fi

	FA_RunCmd cd $1
}

function build_backports()
{
	local KSRC=$1
	local WDIR=$2

	change_work_dir ${WDIR}
	FA_RunCmd ${MAKE} KLIB_BUILD=${KSRC} defconfig-$3
	FA_RunCmd ${MAKE} KLIB_BUILD=${KSRC}
	FA_RunCmd ${MAKE} KLIB_BUILD=${KSRC} KLIB=${OUT} install
}

function build_rtl8192cu()
{
	local OPTS KSRC WDIR
	OPTS="CONFIG_VENDOR_FRIENDLYARM=y CONFIG_PLATFORM_ANDROID=${ANDROID}"
	KSRC=$1
	WDIR=$2

	change_work_dir ${WDIR}
	FA_RunCmd ${MAKE} ${OPTS} KVER=${KREL} KSRC=${KSRC} all
	FA_RunCmd ${MAKE} ${OPTS} KVER=${KREL} KSRC=${KSRC} \
		KLIB=${OUT} install
}

function build_rtl8188eu()
{
	local OPTS KSRC WDIR
	OPTS="CONFIG_VENDOR_FRIENDLYARM=y CONFIG_PLATFORM_ANDROID=${ANDROID}"
	KSRC=$1
	WDIR=$2

	change_work_dir ${WDIR}
	FA_RunCmd ${MAKE} ${OPTS} KVER=${KREL} KSRC=${KSRC} all
	FA_RunCmd ${MAKE} ${OPTS} KVER=${KREL} KSRC=${KSRC} \
		KLIB=${OUT} install
}

function install_kmodules()
{
	change_work_dir $1
	FA_RunCmd ${MAKE} INSTALL_MOD_PATH=${OUT} modules
	FA_RunCmd ${MAKE} INSTALL_MOD_PATH=${OUT} modules_install

	[ ! -f ${OUT}/lib/modules/${KREL}/modules.dep ] && \
		FA_RunCmd depmod -b ${OUT} -E Module.symvers -F System.map -w ${KREL}
}

function create_kmod_tgz()
{
	[ -z $1 ] && exit 0
	local TGZ=$1

	cd ${OUT}/lib && {
		find . -name \*.ko | xargs arm-linux-strip --strip-unneeded
		tar czf ${TGZ}  modules/ &&
			ls -l ${TGZ}
	}
}

# ----------------------------------------------------------
# build for one kernel srctree 

T_COMPAT=${TOP}/backports-4.4.2-1
T_8192CU=${TOP}/rtl8192cu
T_8188EU=${TOP}/rtl8188eus

function build_modules_4()
{
	local KSRC=$1

	check_kernel_dir  ${KSRC}
	KREL=`cd ${KSRC} 2>/dev/null && make kernelrelease`

	install_kmodules  ${KSRC}
	build_backports   ${KSRC} ${T_COMPAT} ${BCFG}
	build_rtl8192cu   ${KSRC} ${T_8192CU}
	build_rtl8188eu   ${KSRC} ${T_8188EU}
}

function clean_all()
{
	if [ ! -z "${OUT}" -a -d "${OUT}/lib/" ]; then
		FA_RunCmd rm -rf ${OUT}/lib/
	fi

	FA_RunCmd rm -rfv    ${T_COMPAT}/.config
	FA_RunCmd ${MAKE} -C ${T_COMPAT} clean
	FA_RunCmd ${MAKE} -C ${T_8192CU} clean
	FA_RunCmd ${MAKE} -C ${T_8188EU} clean
}

# ----------------------------------------------------------

parse_args $@

echo "Work directory: ${TOP}"
echo "       Out dir: ${OUT}"

if [ "${TARGET}" = "clean" ]; then
	clean_all;        exit $?
fi

echo "    Kernel dir: ${KDIR}"
build_modules_4       ${KDIR}

create_kmod_tgz       ${PKG}

