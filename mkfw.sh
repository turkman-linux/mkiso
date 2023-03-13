#!/bin/bash
while getopts -- ':d:' OPTION; do
  case "$OPTION" in
     d)
       export DESTDIR="${OPTARG[@]}"
     ;;
  esac
done

for arg in $@ ; do
    if [[ "$arg" == "--install" || "$arg" == "-i" ]] ; then
        export INSTALL=1
    fi
    if [[ "$arg" == "--update" || "$arg" == "-u" ]] ; then
        export INSTALL=1
        export UPDATE=1
    fi
    if [[ "$arg" == "--remove" || "$arg" == "-r" ]] ; then
        export REMOVE=1
    fi
    if [[ "$arg" == "--version" || "$arg" == "-v" ]] ; then
        export PRINT=1
    fi
    if [[ "$arg" == "--help" || "$arg" == "-h" ]] ; then
        echo "Usage: mkfw [options]"
        echo "  --install / -i : install latest firmwares"
        echo "  --update  / -u : update firmwares"
        echo "  --remove  / -r : remove firmwares"
        echo "  --version / -v : print latest firmware version"
        echo "  --help    / -h : print help message"
        exit 0
    fi
done

src_uri="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/refs/"
tarball=https://git.kernel.org/$(wget -O - ${src_uri} 2>/dev/null | sed "s/.tar.gz'.*/.tar.gz/g;s/.*'//g" | grep "^/pub" | sort -V | tail -n 1)
version=$(echo $tarball | sed "s/.*-//g;s/\..*//g")

if [[ "$PRINT" != "" ]] ; then
    echo $version
    exit 0
elif [[ "$INSTALL" != "" ]] ; then
    if [[ "$UPDATE" != "" ]] ; then
    cur_version=$(cat $DESTDIR/lib/firmware/.version 2>/dev/null)
    if [[ "${cur_version}" == "${version}" ]] ; then
            exit 0
        fi
    fi
    mkdir -p /tmp/mkfw/
    if [[ ! -f /tmp/mkfw/$version.tar.gz ]] ; then
        wget $tarball -O /tmp/mkfw/$version.tar.gz
    fi
    cd /tmp/mkfw/
    tar -xf $version.tar.gz
    make install -C linux-firmware-$version
    echo "$version" > "$DESTDIR/lib/firmware/.version"
elif [[ "$REMOVE" != "" ]] ; then
    rm -rf "$DESTDIR"/lib/firmware
    mkdir -p "$DESTDIR"/lib/firmware
fi
