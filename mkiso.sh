#!/bin/bash
set -e
if [[ "$UID" != "0" ]] ; then
    echo "You must be root!"
    exit 31
fi
umask 022
mkdir isowork/live -p
mkdir isowork/boot/grub -p
if ! which ympstrap >/dev/null ; then
    wget https://gitlab.com/turkman/devel/sources/ymp/-/raw/master/scripts/ympstrap -O /bin/ympstrap
    chmod +x /bin/ympstrap
fi
ympstrap rootfs live-boot linux openrc
ln -s openrc-init rootfs/sbin/init
ln -s agetty rootfs/etc/init.d/agetty.tty1
chroot rootfs rc-update add agetty.tty1
echo -e "31\n31\n" | chroot rootfs passwd
echo "nameserver 1.1.1.1" > rootfs/etc/resolv.conf
if [[ -f custom ]] ; then
    cp custom rootfs/tmp/custom
    chroot rootfs sh -e /tmp/custom
    rm rootfs/tmp/custom
fi
mksquashfs rootfs isowork/live/filesystem.squashfs -comp gzip -wildcards
install rootfs/boot/vmlinuz-* isowork/linux
install rootfs/boot/initrd.img-* isowork/initrd.img
cat > isowork/boot/grub/grub.cfg <<EOF
insmod all_video
menuentry TurkMan {
    linux /linux boot=live quiet
    initrd /initrd.img
}
EOF
grub-mkrescue -o turkman.iso isowork