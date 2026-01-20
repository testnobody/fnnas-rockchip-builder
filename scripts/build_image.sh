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

sudo mkdir -p /mnt/boot /mnt/root /mnt/src

sudo mount $BOOT /mnt/boot
sudo mount $ROOT /mnt/root

log "Copy boot files"
sudo cp $BOOT_SRC/extlinux.conf /mnt/boot/
sudo cp $BOOT_SRC/fnEnv.txt /mnt/boot/
sudo cp $BOOT_SRC/*.dtb /mnt/boot/

log "Copy rootfs"
BASE_LOOP=$(sudo losetup --find --show $BASE_IMG)
sudo mount ${BASE_LOOP}p2 /mnt/src
sudo cp -a /mnt/src/* /mnt/root/
sudo umount /mnt/src
sudo losetup -d $BASE_LOOP

sync
sudo umount /mnt/boot
sudo umount /mnt/root
sudo losetup -d $LOOP

log "Done: $OUT_IMG"
