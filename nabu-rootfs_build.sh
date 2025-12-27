#!/bin/sh
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "rootfs can only be built as root"
  exit 1
fi

VERSION="24.04"
SUITE="noble"
MIRROR="http://archive.ubuntu.com/ubuntu"
BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/${VERSION}/release"

truncate -s 6G rootfs.img
mkfs.ext4 rootfs.img

mkdir -p rootdir
mount -o loop rootfs.img rootdir

wget "${BASE_URL}/ubuntu-base-${VERSION}-base-arm64.tar.gz"
tar xzf ubuntu-base-${VERSION}-base-arm64.tar.gz -C rootdir

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount --bind /proc rootdir/proc
mount --bind /sys rootdir/sys

echo "nameserver 1.1.1.1" > rootdir/etc/resolv.conf
echo "xiaomi-nabu" > rootdir/etc/hostname

cat > rootdir/etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 xiaomi-nabu
EOF

# qemu-user-static
if ! uname -m | grep -q aarch64; then
  apt install -y qemu-user-static binfmt-support
fi

# apt sources
cat > rootdir/etc/apt/sources.list <<EOF
deb ${MIRROR} ${SUITE} main restricted universe multiverse
deb ${MIRROR} ${SUITE}-updates main restricted universe multiverse
deb ${MIRROR} ${SUITE}-security main restricted universe multiverse
EOF

export DEBIAN_FRONTEND=noninteractive

chroot rootdir apt update
chroot rootdir apt upgrade -y

chroot rootdir apt install -y \
  sudo ssh nano bash-completion \
  ubuntu-desktop-minimal \
  grub-efi-arm64 \
  alsa-ucm-conf \
  rmtfs protection-domain-mapper tqftpserv

# kernel & firmware debs
mkdir -p rootdir/tmp
cp xiaomi-nabu-debs_$2/*-xiaomi-nabu.deb rootdir/tmp/

chroot rootdir dpkg -i /tmp/linux-xiaomi-nabu.deb || true
chroot rootdir dpkg -i /tmp/firmware-xiaomi-nabu.deb || true
chroot rootdir dpkg -i /tmp/alsa-xiaomi-nabu.deb || true
chroot rootdir apt -f install -y

# fstab
cat > rootdir/etc/fstab <<EOF
PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=esp /boot/efi vfat umask=0077 0 1
EOF

mkdir -p rootdir/var/lib/gdm
touch rootdir/var/lib/gdm/run-initial-setup

chroot rootdir apt clean

umount rootdir/sys
umount rootdir/proc
umount rootdir/dev/pts
umount rootdir/dev
umount rootdir

rm -rf rootdir

7z a rootfs.7z rootfs.img
