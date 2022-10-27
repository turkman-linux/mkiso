#!/bin/bash
# Kernel builder
# Uses sulix config
#
#
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
LOCAL_VERSION="$(grep "^NAME=" /etc/os-release | cut -f 2 -d '=' | tr '[:upper:]' '[:lower:]'| tr ' ' '-')"
nobuild=0
pkgdir=""

# Options
while getopts -- ':c:v:t:n:o:' OPTION; do
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
   n)
     nobuild=1
     ;;
   o)
     pkgdir="${OPTARG[@]}"
     ;;
   ?)
     echo "Usage: mklinux <options>"
     echo " -h : help message"
     echo " -c : config location"
     echo " -v : kernel version"
     echo " -t : type (linux / libre / xanmod)"
     echo " -l : local version"
     echo " -o : output directory"
     exit 0
     ;;
    esac
done

if [[ "$version" == "" ]] ; then
    version=$(wget -O - https://kernel.org/ | grep "downloadarrow_small.png" | sed "s/.*href=\"//g;s/\".*//g;s/.*linux-//g;s/\.tar.*//g")
    if echo ${version} | grep -e "\.[0-9]*\.0$" ; then
        version=${version::-2}
    fi
fi

#fetch kernel
if [[ $type == libre ]] ; then
    wget -c http://linux-libre.fsfla.org/pub/linux-libre/releases/${version}-gnu/linux-libre-${version}-gnu.tar.xz
    [[ -d linux-${version} ]] || tar -xf linux-libre-${version}-gnu.tar.xz
elif [[ $type == linux ]] ; then
    wget -c https://cdn.kernel.org/pub/linux/kernel/v${version::1}.x/linux-${version}.tar.xz
    # extrack if directory not exists
    [[ -d linux-${version} ]] || tar -xf linux-${version}.tar.xz
elif [[ $type == xanmod ]] ; then    
    wget -c https://github.com/xanmod/linux/archive/${version}-xanmod1.tar.gz
    if [[ -d linux-${version} ]] ; then
        tar -xf ${version}-xanmod1.tar.gz
        mv linux-${version}-xanmod1 linux-${version}
    fi
else
    echo "Type is invaild"
    exit 1
fi
make -C linux-${version} distclean defconfig
# fetch config
if echo "$config" | grep "://" >/dev/null ; then
    wget -c $config -O - > linux-${version}/.config
elif [[ -f $config ]] ; then
    cat $config > linux-${version}/.config
else
    echo "Config not found"
    exit 1
fi

# go kernel build path and clear optionse
cd linux-${version}
unset version
unset config

# Variable definition
VERSION="$(make -s kernelversion)"
if [[ "$pkgdir" == "" ]] ; then
    pkgdir=../build-$type/${VERSION}
if
modulesdir=${pkgdir}/lib/modules/${VERSION}
builddir="${pkgdir}/lib/modules/${VERSION}/build"

# set local version
sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=${LOCAL_VERSION}/g" .config
if [[ $nobuild == 1 ]] ; then
    exit 0
fi

# Building kernel
yes "" | unshare -rufipnm make bzImage -j$(nproc)
unshare -rufipnm make modules -j$(nproc)

# Create directories
mkdir -p "$pkgdir/boot" "$pkgdir/usr/src" "$modulesdir" || true

# install bzImage
install -Dm644 "$(make -s image_name)" "$pkgdir/boot/vmlinuz-${VERSION}"

# install modules
make INSTALL_MOD_PATH="$pkgdir" INSTALL_MOD_STRIP=1 modules_install -j$(nproc)
rm "$modulesdir"/{source,build} || true
depmod --all --verbose --basedir="$pkgdir" "${VERSION}" || true

# install build directories
install -Dt "$builddir" -m644 Makefile Module.symvers System.map vmlinux || true
install .config "$pkgdir/boot/config-${VERSION}"
install -Dt "$builddir/kernel" -m644 kernel/Makefile
install -Dt "$builddir/arch/x86" -m644 arch/x86/Makefile
cp -t "$builddir" -a scripts
install -Dt "$builddir/tools/objtool" tools/objtool/objtool
mkdir -p "$builddir"/{fs/xfs,mm}
ln -s "../../lib/modules/${VERSION}/build" "$pkgdir/usr/src/linux-headers-${VERSION}"

# install libc headers
make headers_install INSTALL_HDR_PATH="$pkgdir/usr"

# install headers
cp -t "$builddir" -a include
cp -t "$builddir/arch/x86" -a arch/x86/include
install -Dt "$builddir/arch/x86/kernel" -m644 arch/x86/kernel/asm-offsets.s
install -Dt "$builddir/drivers/md" -m644 drivers/md/*.h
install -Dt "$builddir/net/mac80211" -m644 net/mac80211/*.h
install -Dt "$builddir/drivers/media/i2c" -m644 drivers/media/i2c/msp3400-driver.h
install -Dt "$builddir/drivers/media/usb/dvb-usb" -m644 drivers/media/usb/dvb-usb/*.h
install -Dt "$builddir/drivers/media/dvb-frontends" -m644 drivers/media/dvb-frontends/*.h
install -Dt "$builddir/drivers/media/tuners" -m644 drivers/media/tuners/*.h
find . -name 'Kconfig*' -exec install -Dm644 {} "$builddir/{}" \;

# clearing
find -L "$builddir" -type l -printf 'Removing %P\n' -delete
find "$builddir" -type f -name '*.o' -printf 'Removing %P\n' -delete
