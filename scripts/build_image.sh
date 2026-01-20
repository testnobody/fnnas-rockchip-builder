#!/usr/bin/env bash
# rootfs size in GiB (from workflow input)
ROOTFS_SIZE_GB=${ROOTFS_SIZE:-8}

# calculate total image size
IMAGE_SIZE="${ROOTFS_SIZE_GB}G"

set -e
source scripts/common.sh
source configs/nanopi-r2s.conf

BOOT_SRC="devices/$SOC/$DEVICE"
BASE_IMG="cache/fnnas.img"
OUT_IMG="fnnas-${DEVICE}.img"

log "Create image"
truncate -s $IMAGE_SIZE $OUT_IMG
LOOP=$(sudo losetup --find --show $OUT_IMG)

log "Write bootloader"
sudo dd if=$BOOT_SRC/idbloader.bin of=$LOOP seek=64 conv=notrunc
sudo dd if=$BOOT_SRC/uboot.img of=$LOOP seek=16384 conv=notrunc
sudo dd if=$BOOT_SRC/trust.bin of=$LOOP seek=24576 conv=notrunc

log "Partition"
sudo parted -s $LOOP mklabel gpt
sudo parted -s $LOOP mkpart boot fat32 $BOOT_START $BOOT_SIZE
sudo parted -s $LOOP mkpart rootfs ext4 $BOOT_SIZE 100%
sudo partprobe $LOOP
sleep 2

BOOT=${LOOP}p1
ROOT=${LOOP}p2

sudo mkfs.vfat $BOOT
sudo mkfs.ext4 $ROOT

# Create mount points
sudo mkdir -p /mnt/boot /mnt/root /mnt/src

# Mount the partitions
sudo mount $BOOT /mnt/boot
sudo mount $ROOT /mnt/root

log "Copy boot files"
sudo cp $BOOT_SRC/extlinux.conf /mnt/boot/
sudo cp $BOOT_SRC/fnEnv.txt /mnt/boot/
sudo cp $BOOT_SRC/*.dtb /mnt/boot/

log "Copy rootfs"

# Attach base image and mount it
BASE_LOOP=$(sudo losetup --find --show --partscan "$BASE_IMG")
sudo partprobe "$BASE_LOOP" || true

# Wait for partitions to appear (max 3 seconds)
for i in 1 2 3 4 5; do
  ls "${BASE_LOOP}"p* >/dev/null 2>&1 && break
  sleep 1
done

# Select the largest ext4 partition for rootfs
SRC_PART=""
SRC_SIZE=0
for p in "${BASE_LOOP}"p*; do
  fstype=$(sudo blkid -o value -s TYPE "$p" 2>/dev/null || true)
  if [ "$fstype" = "ext4" ]; then
    sz=$(sudo blockdev --getsize64 "$p" 2>/dev/null || echo 0)
    if [ "$sz" -gt "$SRC_SIZE" ]; then
      SRC_SIZE="$sz"
      SRC_PART="$p"
    fi
  fi
done

# If no ext4 partition found, fall back to the entire image
if [ -z "$SRC_PART" ]; then
  SRC_PART="$BASE_LOOP"
fi

# Mount rootfs partition
sudo mount "$SRC_PART" /mnt/src

# Use /mnt/src/. to copy contents and avoid empty directory error
sudo cp -a /mnt/src/. /mnt/root/

# Install resize-rootfs.sh and systemd service
sudo install -m 0755 assets/resize-rootfs.sh /mnt/root/usr/local/sbin/resize-rootfs.sh
sudo install -m 0644 assets/resize-rootfs.service /mnt/root/etc/systemd/system/resize-rootfs.service

# Enable the resize-rootfs service to run on first boot
sudo chroot /mnt/root /bin/sh -lc "systemctl enable resize-rootfs.service || true"

# Clean up
sudo umount /mnt/src
sudo losetup -d "$BASE_LOOP"

sync
sudo umount /mnt/boot
sudo umount /mnt/root
sudo losetup -d $LOOP

log "Done: $OUT_IMG"
