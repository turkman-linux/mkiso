#!/bin/bash
set -ex
if [[ "$UID" != "0" ]] ; then
    echo "You must be root!"
    exit 31
fi
umask 022
if [[ -d isowork ]] ; then
    rm -rf isowork
fi
mkdir isowork/live -p
mkdir isowork/boot/grub -p
if [[ "$REPO" == "" ]] ; then
    export REPO='https://gitlab.com/turkman/packages/binary-repo/-/raw/master/$uri'
fi
if ! which ympstrap >/dev/null ; then
    wget https://gitlab.com/turkman/devel/sources/ymp/-/raw/master/scripts/ympstrap -O /bin/ympstrap
    chmod +x /bin/ympstrap
fi
# create rootfs
if [[ ! -f rootfs/etc/os-release ]] ; then
    ympstrap rootfs live-boot linux openrc gnupg kmod mkinitrd eudev gnupg procps-ng
fi
# bind mount
for dir in dev sys proc run ; do
    mount --bind /$dir rootfs/$dir
done
if [[ "${CONFIGURE}" != "0" ]] ; then
    # openrc settings
    ln -s agetty rootfs/etc/init.d/agetty.tty1 || true
    chroot rootfs rc-update add agetty.tty1 || true
    ln -s openrc-init rootfs/sbin/init || true
    # sysctl settings
    rm -f rootfs/bin/sysctl || true
    chroot rootfs rc-update add sysctl sysinit
   # enable live-config service
    chroot rootfs rc-update add live-config
    # system configuration
    echo -e "live\nlive\n" | chroot rootfs passwd
    cat /etc/resolv.conf > rootfs/etc/resolv.conf
    # add gpg key
    chroot rootfs ymp key --add ${REPO/\$uri/ymp-index.yaml.asc} --name=main --allow-oem
    # customize
    if [[ -f custom ]] ; then
        cp custom rootfs/tmp/custom
        chroot rootfs bash -ex /tmp/custom
        rm rootfs/tmp/custom
    elif [[ -d custom ]] ; then
        for file in $(ls custom) ; do
            cp custom/$file rootfs/tmp/custom
            chroot rootfs bash -ex /tmp/custom
            rm rootfs/tmp/custom
        done
    fi
    # clean
    chroot rootfs ymp clean --allow-oem
    find rootfs/var/log -type f -exec rm -f {} \;
    rm rootfs/etc/resolv.conf
fi
# linux-firmware (optional)
if [[ "$FIRMWARE" != "" ]] ; then
    if [ ! -f /tmp/linux-firmware.tar.gz ] ; then
       tarball="https://gitlab.com/kernel-firmware/linux-firmware/-/archive/main/linux-firmware-main.tar.gz"
        wget $tarball -O /tmp/linux-firmware.tar.gz
    fi
    cp -f /tmp/linux-firmware.tar.gz rootfs/tmp/linux-firmware.tar.gz
    cd rootfs/tmp
    tar -xvf linux-firmware.tar.gz
    cd linux-firmware-*
    echo > check_whence.py
    make install dedup DESTDIR="$(realpath ../..)"
    cd ../../..
    rm -rf rootfs/tmp/linux-firmware*
fi
# set permissions
chmod 1777 rootfs/tmp
chmod 700 rootfs/data/user/root
chown root:root rootfs/data/user/root
chmod 111 rootfs/bin
chmod 111 rootfs/sbin
chmod 111 rootfs/usr/bin
chmod 111 rootfs/usr/sbin
chmod 111 rootfs/usr/libexec

# bind unmount
for dir in dev sys proc run ; do
    while umount -lf -R rootfs/$dir ; do : ; done
done
if [[ "$COMPRESS" == 'gzip' ]] ; then
    gzip=1
elif [[ "$COMPRESS" == 'none' ]] ; then
    : Compress disabled
else
    xz=1
fi
# copy kernel and initramfs
for kernel in $(ls rootfs/lib/modules/) ; do
    chroot rootfs mkinitrd -u -z gzip -k "$kernel" -c /etc/initrd/config-live.sh
done
install rootfs/boot/vmlinuz-* isowork/linux
install rootfs/boot/initrd.img-* isowork/initrd.img
# remove initrd from rootfs
rm -f rootfs/boot/initrd.img-* || true
# create squashfs
mksquashfs rootfs isowork/live/filesystem.squashfs  -b 1048576 ${xz:+-comp xz -Xdict-size 100%} ${gzip:+-comp gzip}  -noappend -wildcards
# create grub config
cat > isowork/boot/grub/grub.cfg <<EOF
insmod all_video
terminal_output console
terminal_input console
menuentry TurkMan {
    linux /linux boot=live quiet
    initrd /initrd.img
}
EOF
# create iso image
grub-mkrescue -o turkman.iso isowork \
    --fonts="" --locales="" --compress=gz \
    --install-modules="linux normal fat all_video"
