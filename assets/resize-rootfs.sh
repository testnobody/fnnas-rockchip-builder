#!/bin/sh
set -e

DISK=/dev/mmcblk0
PART=${DISK}p2

# 扩展第2分区到整盘末尾（不改分区起点）
parted -s "$DISK" resizepart 2 100%

# 扩展 ext4 文件系统（支持在线扩容）
resize2fs "$PART"

# 只执行一次：成功后自我禁用
systemctl disable resize-rootfs.service || true
rm -f /etc/systemd/system/resize-rootfs.service || true
rm -f /usr/local/sbin/resize-rootfs.sh || true
