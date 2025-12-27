#!/bin/sh
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "rootfs can only be built as root"
  exit 1
fi

DESKTOP="$1"          # ubuntu-desktop / ubuntu-desktop-minimal
KERNEL="$2"           # 6.7-working
SUITE="mantic"

IMG=rootfs.img
ROOT=rootdir

truncate -s 6G "$IMG"
mkfs.ext4 "$IMG"

mkdir -p "$ROOT"
mount -o loop "$IMG" "$ROOT"

# -------------------------------
# MIRROR FALLBACK (EOL SAFE)
# -------------------------------
MIRRORS="
http://mirror.ucu.ac.ug/ubuntu
http://ke.mirror.ctrldev.net/ubuntu
http://za.archive.ubuntu.com/ubuntu
http://ftp.yzu.edu.tw/Linux/ubuntu
"

for m in $MIRRORS; do
  echo "Testing mirror: $m"
  if wget -q --spider "$m/dists/$SUITE/Release"; then
    MIRROR="$m"
    echo "Using mirror: $MIRROR"
    break
  fi
done

if [ -z "$MIRROR" ]; then
  echo "No working mirror found"
  exit 1
fi

# -------------------------------
# BOOTSTRAP ROOTFS (CORRECT WAY)
# -------------------------------
debootstrap \
  --arch=arm64 \
  --foreign \
  "$SUITE" \
  "$ROOT" \
  "$MIRROR"

# -------------------------------
# QEMU FOR CHROOT
# -------------------------------
if ! uname -m | grep -q aarch64; then
  cp /usr/bin/qemu-aarch64-static "$ROOT/usr/bin/"
fi

mount --bind /dev "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount --bind /proc "$ROOT/proc"
mount --bind /sys "$ROOT/sys"

chroot "$ROOT" /debootstrap/debootstrap --second-stage

# -------------------------------
# APT CONFIG
# -------------------------------
cat > "$ROOT/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE main universe multiverse restricted
deb $MIRROR $SUITE-updates main universe multiverse restricted
deb $MIRROR $SUITE-security main universe multiverse restricted
EOF

echo "nameserver 1.1.1.1" > "$ROOT/etc/resolv.conf"
echo "xiaomi-nabu" > "$ROOT/etc/hostname"

export DEBIAN_FRONTEND=noninteractive

chroot "$ROOT" apt-get update
chroot "$ROOT" apt-get upgrade -y

# -------------------------------
# BASE PACKAGES
# -------------------------------
chroot "$ROOT" apt-get install -y \
  sudo ssh nano bash-completion \
  systemd-sysv dbus \
  p7zip-full \
  grub-efi-arm64

# -------------------------------
# DESKTOP (MINIMAL ÖNERİLİR)
# -------------------------------
if [ "$DESKTOP" = "ubuntu-desktop" ]; then
  chroot "$ROOT" apt-get install -y ubuntu-desktop-minimal
fi

# -------------------------------
# DEVICE PACKAGES
# -------------------------------
chroot "$ROOT" apt-get install -y \
  rmtfs protection-domain-mapper tqftpserv || true

sed -i '/ConditionKernelVersion/d' \
  "$ROOT/lib/systemd/system/pd-mapper.service" || true

# -------------------------------
# KERNEL DEBS
# -------------------------------
cp xiaomi-nabu-debs_"$KERNEL"/*-xiaomi-nabu.deb "$ROOT/tmp/"
chroot "$ROOT" dpkg -i /tmp/*-xiaomi-nabu.deb || true
rm -f "$ROOT/tmp/"*.deb

# -------------------------------
# CLEANUP
# -------------------------------
chroot "$ROOT" apt-get clean

umount "$ROOT/sys"
umount "$ROOT/proc"
umount "$ROOT/dev/pts"
umount "$ROOT/dev"
umount "$ROOT"

rmdir "$ROOT"

# -------------------------------
# ARCHIVE (HOST SIDE)
# -------------------------------
7z a rootfs.7z rootfs.img

echo 'cmdline: root=PARTLABEL=linux'
