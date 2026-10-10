#!/bin/bash

set -e

TARGET=target/emmc
OUTPUT=output

# 上次运行若在卸载前失败，会残留挂载的 /dev /proc /sys；
# 先卸载再删除，否则 rm -rf 会遍历已挂载的 proc/sys 报 Operation not permitted
umount -R ${TARGET}/dev 2>/dev/null || true
umount -R ${TARGET}/proc 2>/dev/null || true
umount -R ${TARGET}/sys 2>/dev/null || true

rm -rf ${TARGET}
mkdir -p ${TARGET}

# 基于 Debian 13 (trixie) 构建 ws215i 的基础 rootfs。
# debootstrap 会在 ${TARGET} 内创建最小基础系统（含 systemd），
# 随后 chroot 安装其余软件包和 ws215i 定制内核。
debootstrap --variant=minbase --arch=amd64 trixie ${TARGET} http://deb.debian.org/debian
cp assets/linux-image-4.3.3.001+_001_amd64.deb ${TARGET}
cp assets/sources.list ${TARGET}/etc/apt/sources.list

touch ${TARGET}/etc/firstboot

cat <<EOF > ${TARGET}/lib/systemd/system/wisnuc-firstboot.service
[Unit]
Description=Wisnuc First Boot
Conflicts=shutdown.target
ConditionPathExists=/etc/firstboot

[Service]
Type=oneshot
# localectl does not work even in login shell
ExecStartPre=/usr/bin/timedatectl set-timezone "Asia/Shanghai"
ExecStart=/usr/bin/timedatectl set-ntp true
ExecStartPost=/bin/rm /etc/firstboot

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > ${TARGET}/etc/systemd/timesyncd.conf
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation; either version 2.1 of the License, or
#  (at your option) any later version.
#
# Entries in this file show the compile time defaults.
# You can change settings by editing this file.
# Defaults can be restored by simply deleting this file.
#
# See timesyncd.conf(5) for details.

[Time]
#NTP=
FallbackNTP=ntp.debian.org
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
# 直接复制宿主的 /etc/resolv.conf，避免硬编码 127.0.1.1
# （那是 Ubuntu 16.04 的 systemd-resolved stub，现代宿主上不生效）。
# 该文件在脚本末尾会被替换为 systemd-resolved 的符号链接（用于最终镜像）。
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

# chroot_setup
mount -o bind   /dev  ${TARGET}/dev
mount -t proc   proc  ${TARGET}/proc
mount -t sysfs  sys   ${TARGET}/sys

chroot ${TARGET} /bin/bash -c "apt update"
# Debian 13 中 systemd-resolved / systemd-timesyncd 是独立子包，minbase 不默认安装，需显式装上
# （否则 systemd-resolved.service unit 不存在，enable 会失败；timesyncd 供 firstboot 的 set-ntp 使用）
chroot ${TARGET} /bin/bash -c "apt -y install sudo initramfs-tools openssh-server parted tzdata net-tools iputils-ping systemd-resolved systemd-timesyncd"
chroot ${TARGET} /bin/bash -c "apt -y install avahi-daemon avahi-utils udisks2"
chroot ${TARGET} /bin/bash -c "apt -y install rsyslog"

chroot ${TARGET} /bin/bash -c "useradd wisnuc -b /home -m -s /bin/bash"
chroot ${TARGET} /bin/bash -c "echo wisnuc:wisnuc | chpasswd"
chroot ${TARGET} /bin/bash -c "adduser wisnuc sudo"

# 安装 ws215i 定制内核（4.3.3）并 hold，避免被后续 apt 升级/替换掉。
# Debian 13 没有 Ubuntu 的 linux-image-generic/linux-headers-generic meta 包
# （debootstrap minbase 也不安装 meta 内核），因此直接 hold 定制内核包本身。
chroot ${TARGET} /bin/bash -c "dpkg -i linux-image-4.3.3.001+_001_amd64.deb"
chroot ${TARGET} /bin/bash -c "apt-mark hold linux-image-4.3.3.001+"

# This does not work in chroot-ed environment.
# chroot ${TARGET} /bin/bash -c "timedatectl timedatectl set-timezone Asia/Shanghai"
# see https://wiki.archlinux.org/index.php/time
# This does not work either.
# chroot ${TARGET} /bin/bash -c "ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"

chroot ${TARGET} /bin/bash -c "systemctl enable systemd-networkd"
chroot ${TARGET} /bin/bash -c "systemctl enable systemd-resolved"
chroot ${TARGET} /bin/bash -c "systemctl enable wisnuc-firstboot"
# samba/minidlna 不再安装，故无需（也无法）禁用其服务

ln -s vmlinuz-4.3.3.001+ ${TARGET}/boot/bzImage
ln -s initrd.img-4.3.3.001+ ${TARGET}/boot/ramdisk
echo "console=tty0 console=ttyS0,115200 root=/dev/mmcblk0p1 rootwait" > ${TARGET}/boot/cmdline
echo "/dev/mmcblk0p1 / ext4 errors=remount-ro 0 1" > ${TARGET}/etc/fstab

chroot ${TARGET} /bin/bash -c "apt clean"

umount ${TARGET}/sys
umount ${TARGET}/proc
umount ${TARGET}/dev

rm -rf ${TARGET}/linux-image-4.3.3.001+_001_amd64.deb

# remove resolv.conf used in chroot
rm ${TARGET}/etc/resolv.conf
# create symbolic link as systemd-resolved requires.
ln -sf /run/systemd/resolve/resolv.conf ${TARGET}/etc/resolv.conf

tar czf ${OUTPUT}/ws215i-debian13-rootfs-emmc-base.tar.gz -C ${TARGET} .

echo done
