#!/bin/bash

# this cannot be used for fdisk will fail
# set -e

UUID=7dec5069-3524-4a8f-b838-ee00613cd30b
MNT=tmp/mnt
TMP=tmp/imagify
OUTPUT=output

# 前置检查：build-image 硬性依赖 loop device、完整 /dev 和 mount 能力，
# 在容器/受限宿主上不可用，提前给出明确报错而不是一路失败。
if [ ! -e /dev/zero ]; then
  echo "ERROR: /dev/zero 不存在，当前 /dev 不完整。" >&2
  echo "  build-image.sh 需要 loop device 和 mount 能力，" >&2
  echo "  请在物理机/虚拟机（或 --privileged 且加载 loop 模块的容器）上运行。" >&2
  exit 1
fi
if ! losetup -f >/dev/null 2>&1; then
  echo "ERROR: 无法分配 loop 设备，当前环境不支持。" >&2
  echo "  build-image.sh 依赖 loop device（losetup）创建镜像，" >&2
  echo "  请在物理机/虚拟机（或 --privileged 且加载 loop 模块的容器）上运行。" >&2
  exit 1
fi
command -v tree >/dev/null 2>&1 || echo "WARN: 未安装 tree，仅影响最后的目录树打印（可选：apt install tree）"

mkdir -p tmp
rm -rf $TMP
mkdir $TMP

echo "argument $1"

if [ "$1" == "--debug" ] || [ "$1" == "-d" ]; then
  COUNT=2048
  IMAGEFILE=tmp/imagefile-debug
else
  COUNT=1024
  IMAGEFILE=tmp/imagefile
fi

losetup -d /dev/loop0

rm -rf $TMP
mkdir -p $TMP
mkdir -p $MNT

echo "create $IMAGEFILE"
rm -rf $IMAGEFILE
dd if=/dev/zero of=$IMAGEFILE bs=1M count=${COUNT}

echo "set up loop device"
losetup /dev/loop0 $IMAGEFILE 

echo "fdisk"
(
echo o # Create a new empty DOS partition table
echo n # Add a new partition
echo p # Primary partition
echo 1 # Partition number
echo   # First sector (Accept default: 1)
echo   # Last sector (Accept default: varies)
echo w # Write changes
) | fdisk /dev/loop0

echo "partprobe"
partprobe /dev/loop0

echo "make ext4 file system"
mkfs.ext4 -U $UUID /dev/loop0p1

echo "mount"
mount -t ext4 /dev/loop0p1 $MNT

if [ "$1" == "--debug" ] || [ "$1" == "-d" ]; then
  echo "untar $OUTPUT/ws215i-debian13-rootfs-burn-base-debug.tar.gz" 
  tar xzf $OUTPUT/ws215i-debian13-rootfs-burn-base-debug.tar.gz -C $MNT
else
  echo "untar $OUTPUT/ws215i-debian13-rootfs-burn-base.tar.gz" 
  tar xzf $OUTPUT/ws215i-debian13-rootfs-burn-base.tar.gz -C $MNT
fi

echo "cp $OUTPUT/ws215i-debian13-rootfs-emmc-base.tar.gz" 
cp $OUTPUT/ws215i-debian13-rootfs-emmc-base.tar.gz ${MNT}/wisnuc

sync
umount $MNT
losetup -d /dev/loop0

# for append build timestamp
# date +"%y%m%d-%H%M%S" -> 180104-164540
TIMESTAMP=$(date +"%y%m%d-%H%M%S")

if [ "$1" == "--debug" ] || [ "$1" == "-d" ]; then
  FILENAME=ws215i-debian13-build-${TIMESTAMP}-debug.img
else
  FILENAME=ws215i-debian13-build-${TIMESTAMP}.img
fi

mv $IMAGEFILE $OUTPUT/$FILENAME

echo "$OUTPUT/$FILENAME successfully created"

tree $OUTPUT -L 3
