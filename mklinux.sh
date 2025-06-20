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
     builddir=$(realpath "${OPTARG[@]}")
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

builddir=$(realpath $builddir)

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

    yes "" | make -C "$builddir" config

	  cd "$builddir"

    # embed all filesystem modules
    grep "^CONFIG_[A-Z0-9]*_FS=m" .config  | cut -f1 -d"=" | while read cfg ; do
        ./scripts/config --enable $cfg
    done
    # uncompress modules
    grep "^CONFIG_KERNEL_[A-Z]*" .config  | cut -f1 -d"=" | while read cfg ; do
        ./scripts/config --disable $cfg
    done

    # uncompress modules
    grep "^CONFIG_MODULE_COMPRESS_[A-Z]*" .config  | cut -f1 -d"=" | while read cfg ; do
        ./scripts/config --disable $cfg
    done
	  ./scripts/config --disable CONFIG_MODULE_COMPRESS

	  # set local version
	  sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"${LOCAL_VERSION}\"/g" .config

	  # enable gzip and uncompress modules
	  ./scripts/config --enable CONFIG_MODULE_DECOMPRESS

    # remove default hostname
    sed -i "s/^CONFIG_DEFAULT_HOSTNAME=.*/CONFIG_DEFAULT_HOSTNAME=\"localhost\"/g" .config

    # disable hibernate
    ./scripts/config --disable CONFIG_HIBERNATION
    ./scripts/config --disable CONFIG_HIBERNATION_SNAPSHOT_DEV
    ./scripts/config --disable CONFIG_HIBERNATE_CALLBACKS
    # disable signinig
    ./scripts/config --disable CONFIG_MODULE_SIG_ALL
    # enable some stuff
    ./scripts/config --enable CONFIG_EMBEDDED
    ./scripts/config --enable CONFIG_LOGO
    ./scripts/config --enable CONFIG_LOGO_LINUX_MONO
    ./scripts/config --enable CONFIG_LOGO_LINUX_VGA16
    ./scripts/config --enable CONFIG_LOGO_LINUX_CLUT224

    # embed all filesystem modules
    grep "^CONFIG_[A-Z0-9]*_FS=m" .config  | cut -f1 -d"=" | while read cfg ; do
        ./scripts/config --enable $cfg
    done

    # disable selinux
    grep "^CONFIG_SECURITY_SELINUX_*" .config  | cut -f1 -d"=" | while read cfg ; do
        ./scripts/config --disable $cfg
    done

    # disable zstd
    grep "^CONFIG_.*ZSTD.*" .config  | cut -f1 -d"=" | while read cfg ; do
        ./scripts/config --disable $cfg
    done


    yes "" | make -C "$builddir" config
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
	$e make all -j$(nproc)
fi

if [[ "${install_vmlinuz}" == "1" ]] ; then
	# install bzImage
	mkdir -p "$pkgdir/boot"
	install -Dm644 "$(make -s image_name)" "$pkgdir/boot/vmlinuz-${VERSION}"
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
	install -Dt "$builddir" -m644 Makefile Module.symvers System.map vmlinux
fi

if [[ "${install_header}" == "1" ]] ; then
	# install libc headers
	mkdir -p "$pkgdir/usr/include/linux"
    cp -v -t "$pkgdir/usr/include/" -a include/linux/
    cp -v -t "$pkgdir/usr/" -a tools/include
	make headers_install INSTALL_HDR_PATH="$pkgdir/usr"
fi

if [[ "${install_modules}" == "1" ]] ; then
    # install headers
    mkdir -p "$builddir" "$builddir/arch/$arch"
    cp -v -t "$builddir" -a include
    cp -v -t "$builddir/arch/$arch" -a arch/$arch/include
    install -Dt "$builddir/arch/$arch/kernel" -m644 arch/$arch/kernel/asm-offsets.*
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


if [[ "${install_modules}" == "1" || "${install_vmlinuz}" == "1" ]] ; then
	# clearing
	find -L "$builddir" -type l -printf 'Removing %P\n' -delete
	find "$builddir" -type f -name '*.o' -printf 'Removing %P\n' -delete
fi

if [[ -d "$builddir" ]] ; then
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

fi

if [[ -f "$builddir/vmlinux" ]] ; then
    echo "Stripping vmlinux..."
    strip "$builddir/vmlinux"
fi

