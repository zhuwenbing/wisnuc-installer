#!/bin/bash

set -e

UUID=7dec5069-3524-4a8f-b838-ee00613cd30b

TARGET=target/burn
OUTPUT=output


# 上次运行若在卸载前失败，会残留挂载的 /dev /proc /sys；
# 先卸载再删除，否则 rm -rf 会遍历已挂载的 proc/sys 报 Operation not permitted
umount -R ${TARGET}/dev 2>/dev/null || true
umount -R ${TARGET}/proc 2>/dev/null || true
umount -R ${TARGET}/sys 2>/dev/null || true

rm -rf ${TARGET}
mkdir -p ${TARGET}/wisnuc

# 基于 Debian 13 (trixie) 构建烧录 U 盘的最小文件系统。
# USB 烧录盘本身也是一个包含完整 rootfs 的 Debian 运行系统，不只是 ramdisk。
debootstrap --variant=minbase --arch=amd64 trixie ${TARGET} http://deb.debian.org/debian

cp assets/linux-image-4.3.3.001+_001_amd64.deb ${TARGET}

cp assets/imageburn.sh ${TARGET}/wisnuc

cat <<EOF > ${TARGET}/etc/apt/sources.list
deb http://mirrors.aliyun.com/debian/ trixie main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ trixie-updates main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian-security trixie-security main contrib non-free non-free-firmware
EOF

# minbase 基础系统不会预建 /etc/systemd/network，需先创建
mkdir -p ${TARGET}/etc/systemd/network
cat <<EOF > ${TARGET}/etc/systemd/network/wired.network
[Match]
Name=en*
[Network]
DHCP=ipv4
EOF

# 临时 DNS（chroot 期间使用）：chroot 共享宿主网络命名空间，
# 直接复制宿主的 /etc/resolv.conf，避免硬编码 127.0.1.1 导致无法解析镜像源。
cp /etc/resolv.conf ${TARGET}/etc/resolv.conf

cat <<EOF > ${TARGET}/etc/hosts
127.0.0.1 localhost
127.0.1.1 wisnuc

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

cat <<EOF > ${TARGET}/etc/hostname
wisnuc
EOF

cat <<EOF > ${TARGET}/lib/systemd/system/wisnuc-imageburn.service
[Unit]
Description=wisnuc ws215i imageburn

[Service]
Type=oneshot
ExecStart=/wisnuc/imageburn.sh

[Install]
WantedBy=multi-user.target
EOF

# chroot_setup
mount -o bind   /dev  ${TARGET}/dev
mount -t proc   proc  ${TARGET}/proc
mount -t sysfs  sys   ${TARGET}/sys

chroot ${TARGET} /bin/bash -c "apt update"
chroot ${TARGET} /bin/bash -c "apt -y install initramfs-tools parted"
chroot ${TARGET} /bin/bash -c "dpkg -i linux-image-4.3.3.001+_001_amd64.deb"

# this is not necessary, install kernel will update initramfs automatically
# chroot ${TARGET} /bin/bash -c "update-initramfs -u -k all"

if [ "$1" == "--debug" ] || [ "$1" == "-d" ]; then
  echo "install extra packages"
  # debug 模式下 enable systemd-resolved，需显式安装该子包（minbase 不默认装）
  chroot ${TARGET} /bin/bash -c "apt -y install sudo openssh-server net-tools iputils-ping parted vim systemd-resolved"
  chroot ${TARGET} /bin/bash -c "useradd wisnuc -b /home -m -s /bin/bash"
  chroot ${TARGET} /bin/bash -c "echo wisnuc:wisnuc | chpasswd"
  chroot ${TARGET} /bin/bash -c "adduser wisnuc sudo"
  chroot ${TARGET} /bin/bash -c "systemctl enable systemd-networkd"
  chroot ${TARGET} /bin/bash -c "systemctl enable systemd-resolved"
else
  echo "skip extra packages and enable auto-burn"
  chroot ${TARGET} /bin/bash -c "systemctl enable wisnuc-imageburn"
fi

ln -s vmlinuz-4.3.3.001+ ${TARGET}/boot/bzImage
ln -s initrd.img-4.3.3.001+ ${TARGET}/boot/ramdisk
echo "console=tty0 console=ttyS0,115200 root=UUID=${UUID} rootwait" > ${TARGET}/boot/cmdline
echo "UUID=${UUID} / ext4 errors=remount-ro 0 1" > ${TARGET}/etc/fstab

chroot ${TARGET} /bin/bash -c "apt clean"

umount ${TARGET}/sys
umount ${TARGET}/proc
umount ${TARGET}/dev

rm ${TARGET}/linux-image-4.3.3.001+_001_amd64.deb

if [ "$1" == "--debug" ] || [ "$1" == "-d" ]; then
  TARNAME=ws215i-debian13-rootfs-burn-base-debug.tar.gz
else
  TARNAME=ws215i-debian13-rootfs-burn-base.tar.gz
fi

echo "tar $OUTPUT/$TARNAME"
tar czf $OUTPUT/$TARNAME -C ${TARGET} .
 
echo "done"
