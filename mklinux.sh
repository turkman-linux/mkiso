#!/bin/bash
# Kernel builder
# Uses archlinux config
#
#
write_help(){
     echo "Usage: mklinux <options>"
     echo " -c                   : config location"
     echo " -v                   : kernel version"
     echo " -t                   : type (linux / libre / xanmod / local)"
     echo " -l                   : local version"
     echo " -o                   : output directory"
     echo " -w                   : work directory"
     echo " -s                   : UTS sysname"
     echo " -h --help            : help message"
     echo " -y --yes             : disable questions"
     echo " -n --no-build        : do not build"
     echo " -i --install-all     : install vmlinuz, header and module files"
     echo " -f --install-headers : install header files"
     echo " -q --install-modules : install module files"
     echo " -x --install-vmlinuz : install vmlinuz file"
     echo " -g --self-install    : install mklinux on system"
}

# Initial stages
set -e
for cmd in bc wget gcc cpio tar unshare ; do
    if ! which $cmd &>/dev/null ; then
        echo $cmd not found
        exit 1
    fi
done
# Default variables
config=./config
type=libre
LOCAL_VERSION=""
nobuild=0
pkgdir=""
sysname="Linux"
workdir="/tmp/mklinux/"
builddir=""
curdir="$PWD/"
# Install variables
install_header=""

# Options
while getopts -- ':c:v:t:o:s:b:' OPTION; do
  case "$OPTION" in
   c)
      config="${OPTARG[@]}"
      ;;
   v)
      version="${OPTARG[@]}"
      ;;
   t)
     type="${OPTARG[@]}"
     ;;
   l)
     LOCAL_VERSION="${OPTARG[@]}"
     ;;
   o)
     pkgdir=$(realpath "${OPTARG[@]}")
     ;;
   s)
     sysname="${OPTARG[@]}"
     ;;
   w)
     workdir=$(realpath "${OPTARG[@]}")
     ;;
   b)
     builddir="${OPTARG[@]}"
     ;;
    esac
done
# Other options
for arg in $@ ; do
    if [[ "$arg" == "--yes" || "$arg" == "-y" ]] ; then
        yes=1
    elif [[ "$arg" == "--install-headers" || "$arg" == "-f" ]] ; then
        install_header=1
    elif [[ "$arg" == "--install-modules" || "$arg" == "-q" ]] ; then
        install_modules=1
    elif [[ "$arg" == "--install-vmlinuz" || "$arg" == "-x" ]] ; then
        install_vmlinuz=1
    elif [[ "$arg" == "--install-all" || "$arg" == "-i" ]] ; then
        install_header=1
        install_modules=1
        install_vmlinuz=1
    elif [[ "$arg" == "--no-build" || "$arg" == "-n" ]] ; then
        no_build=1
    elif [[ "$arg" == "--help" || "$arg" == "-h" ]] ; then
        write_help
        exit 0
    elif [[ "$arg" == "--self-install" || "$arg" == "-g" ]] ; then
        mkdir -p "$pkgdir"/usr/bin/
        exec install "$0" "$pkgdir"/usr/bin/mklinux
    fi
done


if [[ $UID -eq 0 && "$ALLOWROOT" == "" ]] ; then
    echo "Root build in not allowed!"
    echo "If you want to build with root use \"ALLOWROOT=1 mklinux ...\""
    exit 1
fi

if [[ "$version" == "" && type != "local" ]] ; then
    version=$(wget -O - https://kernel.org/ 2>/dev/null | grep "downloadarrow_small.png" | sed "s/.*href=\"//g;s/\".*//g;s/.*linux-//g;s/\.tar.*//g")
    if echo ${version} | grep -e "\.[0-9]*\.0$" ; then
        version=${version::-2}
    fi
fi

if [[ "$builddir" == "" ]] ; then
    builddir=linux-${version}
fi

# write info and confirm
echo "Build info:"
echo "  version         : $version"
echo "  type            : $type"
echo "  output          : $pkgdir"
echo "  build directory : $builddir"
echo "  local version   : ${LOCAL_VERSION}"
echo "  config          : $config"
if [[ "$yes" == "" ]] ; then
    echo -n "Confirm? [Y/n] "
    read -n 1 c
    if [[ "$c" != "y" && "$c" != "Y" ]] ; then
        exit 1
    fi
fi

mkdir -p "$workdir"
cd "$workdir"

#fetch kernel
if [[ $type == libre ]] ; then
    [[ -f linux-libre-${version}-gnu.tar.xz ]] || wget -c http://linux-libre.fsfla.org/pub/linux-libre/releases/${version}-gnu/linux-libre-${version}-gnu.tar.xz
    [[ -d "$builddir" ]] || tar -xf linux-libre-${version}-gnu.tar.xz
    [[ "linux-${version}" ==  "$builddir" ]] || mv linux-${version} $builddir
elif [[ $type == linux ]] ; then
    [[ -f linux-${version}.tar.xz ]] || wget -c https://cdn.kernel.org/pub/linux/kernel/v${version::1}.x/linux-${version}.tar.xz
    # extrack if directory not exists
    [[ -d "$builddir" ]] || tar -xf linux-${version}.tar.xz
    [[ "linux-${version}" ==  "$builddir" ]] || mv linux-${version} $builddir
elif [[ $type == xanmod ]] ; then    
    [[ -f ${version}-xanmod1.tar.gz ]] || wget -c https://github.com/xanmod/linux/archive/${version}-xanmod1.tar.gz
    if [[ -d "$builddir" ]] ; then
        [[ -d "$builddir" ]] || tar -xf ${version}-xanmod1.tar.gz
        [[ "linux-${version}-xanmod1" ==  "$builddir" ]] || mv linux-${version}-xanmod1 "$builddir"
    fi
elif [[ $type == local ]] ; then
    if [[ ! -d "$builddir" ]] ; then
        echo "Build directory is not exists"
        exit 1
    fi
else
    echo "Type is invaild"
    exit 1
fi

if [[ "${no_build}" == "" ]] ; then
	if [[ "$sysname" != "Linux" ]] ; then
		sed -i "s/#define UTS_SYSNAME .*/#define UTS_SYSNAME \"$sysname\"/g" linux-${version}//include/linux/uts.h
	fi

	make -C "$builddir" distclean defconfig
	# fetch config
	if echo "$config" | grep "://" >/dev/null ; then
		wget -c $config -O - > "$builddir"/.config
	elif [[ -f $config ]] ; then
		cat $config > "$builddir"/.config
	else
		echo "Config not found"
		exit 1
	fi

	# set local version
	sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=${LOCAL_VERSION}/g" "$builddir"/.config
	# remove zstd stuff from config
	sed -i "s/.*ZSTD.*//g" "$builddir"/.config
    # remove default hostname
    sed -i "s/^CONFIG_DEFAULT_HOSTNAME=.*//g" "$builddir"/.config
    # disable hibernate
    sed -i "s/CONFIG_HIBERNATION=.*/# CONFIG_HIBERNATION is not set/g" "$builddir"/.config
    sed -i "s/CONFIG_HIBERNATION_SNAPSHOT_DEV=.*/# CONFIG_HIBERNATION_SNAPSHOT_DEV is not set/g" "$builddir"/.config
    sed -i "s/CONFIG_HIBERNATE_CALLBACKS=.*/# CONFIG_HIBERNATE_CALLBACKS is not set/g" "$builddir"/.config
fi

# go kernel build path
cd "$builddir"

# clear options
unset builddir
unset version
unset config

# Variable definition
export KBUILD_BUILD_TIMESTAMP="0"
export EXTRAVERSION="mklinux"
export LANG=C
export LC_ALL=C
VERSION="$(make -s kernelversion)"
if [[ "$pkgdir" == "" ]] ; then
    pkgdir="$curdir"../build-$type/${VERSION}
fi
modulesdir=${pkgdir}/lib/modules/${VERSION}
builddir="${pkgdir}/lib/modules/${VERSION}/build"
arch=$(uname -m)
case $arch in
    x86_64)
      arch=x86
      ;;
   aarch64)
     arch=arm64
     ;;
esac

if [[ "${no_build}" == "" ]] ; then
	# Building kernel
	if [[ "$ALLOWROOT" == "" ]] ; then
		e="unshare -rufipnm"
	fi
	yes "" | $e make all -j$(nproc)
fi

if [[ "${install_vmlinuz}" == "1" ]] ; then
	# install bzImage
	mkdir -p "$pkgdir/boot"
	install -Dm644 "$(make -s image_name)" "$pkgdir/boot/vmlinuz-${VERSION}"
	install -Dt "$builddir" -m644 Makefile Module.symvers System.map vmlinux || true
fi

if [[ "${install_modules}" == "1" ]] ; then
	# install modules
	mkdir -p "$modulesdir"
	mkdir -p "$pkgdir/usr/src"
	make INSTALL_MOD_PATH="$pkgdir" INSTALL_MOD_STRIP=1 modules_install -j$(nproc)
	rm "$modulesdir"/{source,build} || true
	depmod --all --verbose --basedir="$pkgdir" "${VERSION}" || true
	# install build directories
	install .config "$pkgdir/boot/config-${VERSION}"
	install -Dt "$builddir/kernel" -m644 kernel/Makefile
	install -Dt "$builddir/arch/$arch" -m644 arch/$arch/Makefile
	cp -t "$builddir" -a scripts
	install -Dt "$builddir/tools/objtool" tools/objtool/objtool
	mkdir -p "$builddir"/{fs/xfs,mm}
	ln -s "../../lib/modules/${VERSION}/build" "$pkgdir/usr/src/linux-headers-${VERSION}"
fi

if [[ "${install_header}" == "1" ]] ; then
	# install libc headers
	make headers_install INSTALL_HDR_PATH="$pkgdir/usr"
        if [[ "${install_modules}" == "1" ]] ; then
		# install headers
		cp -t "$builddir" -a include
		cp -t "$builddir/arch/$arch" -a arch/$arch/include
		install -Dt "$builddir/arch/$arch/kernel" -m644 arch/$arch/kernel/asm-offsets.s
		install -Dt "$builddir/drivers/md" -m644 drivers/md/*.h
		install -Dt "$builddir/net/mac80211" -m644 net/mac80211/*.h
		install -Dt "$builddir/drivers/media/i2c" -m644 drivers/media/i2c/msp3400-driver.h
		install -Dt "$builddir/drivers/media/usb/dvb-usb" -m644 drivers/media/usb/dvb-usb/*.h
		install -Dt "$builddir/drivers/media/dvb-frontends" -m644 drivers/media/dvb-frontends/*.h
		install -Dt "$builddir/drivers/media/tuners" -m644 drivers/media/tuners/*.h
		# https://bugs.archlinux.org/task/71392
		install -Dt "$builddir/drivers/iio/common/hid-sensors" -m644 drivers/iio/common/hid-sensors/*.h
		find . -name 'Kconfig*' -exec install -Dm644 {} "$builddir/{}" \;
	fi
fi

if [[ "${install_modules}" == "1" || "${install_vmlinuz}" == "1" ]] ; then
	# clearing
	find -L "$builddir" -type l -printf 'Removing %P\n' -delete
	find "$builddir" -type f -name '*.o' -printf 'Removing %P\n' -delete
fi

while read -rd '' file; do
    case "$(file -Sib "$file")" in
        application/x-sharedlib\;*)      # Libraries (.so)
            strip "$file" ;;
        application/x-executable\;*)     # Binaries
            strip "$file" ;;
        application/x-pie-executable\;*) # Relocatable binaries
            strip "$file" ;;
    esac
done < <(find "$builddir" -type f -perm -u+x ! -name vmlinux -print0)

if [[ -f "$builddir/vmlinux" ]] ; then
    echo "Stripping vmlinux..."
    strip "$builddir/vmlinux"
fi

