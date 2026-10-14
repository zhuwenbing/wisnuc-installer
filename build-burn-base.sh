#!/bin/bash

set -e

# 避免 chroot 内 apt/dpkg 时 debconf 弹 Dialog/Readline 前端导致：
#   debconf: unable to initialize frontend: Dialog/Readline
#   Can not write log (Is /dev/pts mounted?) - posix_openpt (19: No such device)
# 这两个变量会被 chroot 继承，apt/dpkg/debconf 全部走非交互模式。
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

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
# 国内镜像源（清华大学 TUNA HTTPS）：
#   - stage 1 在宿主机上下载 .deb，依赖宿主机自带 ca-certificates 做 TLS 校验；
#   - --include=ca-certificates 把 CA 包一并装进 chroot，这样后续 chroot 内
#     apt update / apt install 走 HTTPS 时不会因为 chroot 缺 CA 而握手失败。
debootstrap --variant=minbase --arch=amd64 --include=ca-certificates \
  trixie ${TARGET} https://mirrors.tuna.tsinghua.edu.cn/debian/

cp assets/linux-image-5.10.1.001+_5.10.1.001+-3_amd64.deb ${TARGET}

cp assets/imageburn.sh ${TARGET}/wisnuc

# debootstrap 会按命令行 URL 写一份 legacy /etc/apt/sources.list（只有 main 组件），
# 我们用 DEB822 格式的完整源（含 updates / security / non-free 等）覆盖它，
# 因此先删掉 debootstrap 写的那份，避免双源重复。
rm -f ${TARGET}/etc/apt/sources.list
mkdir -p ${TARGET}/etc/apt/sources.list.d
cat <<EOF > ${TARGET}/etc/apt/sources.list.d/debian.sources
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
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
# bind /dev 只带过来 /dev/null /dev/console 等静态节点，不带 /dev/pts；
# 不挂 devpts 时个别包脚本会调 posix_openpt 报 (19: No such device)。
mkdir -p ${TARGET}/dev/pts
mount -o bind   /dev  ${TARGET}/dev
mount -t devpts devpts ${TARGET}/dev/pts
mount -t proc   proc  ${TARGET}/proc
mount -t sysfs  sys   ${TARGET}/sys

# chroot 构建期间禁止通过 invoke-rc.d 启动/重载系统服务。
# 否则 dbus / avahi-daemon 等包的 postinst 会尝试连 /run/dbus/system_bus_socket，
# 在 chroot 里打印 "Failed to connect to socket ..." 这种无害但吓人的日志。
# exit 101 = Debian Policy 规定的 "policy denied"，invoke-rc.d 看到就跳过。
# 注意：只拦截 invoke-rc.d，不影响 chroot 里的 `systemctl enable`（enable 只是写符号链接）。
cat <<EOF > ${TARGET}/usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF
chmod +x ${TARGET}/usr/sbin/policy-rc.d

chroot ${TARGET} /bin/bash -c "apt update"
chroot ${TARGET} /bin/bash -c "apt -y install initramfs-tools parted"
chroot ${TARGET} /bin/bash -c "dpkg -i linux-image-5.10.1.001+_5.10.1.001+-3_amd64.deb"

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

ln -s vmlinuz-5.10.1.001+ ${TARGET}/boot/bzImage
ln -s initrd.img-5.10.1.001+ ${TARGET}/boot/ramdisk
echo "console=tty0 console=ttyS0,115200 root=UUID=${UUID} rootwait" > ${TARGET}/boot/cmdline
echo "UUID=${UUID} / ext4 errors=remount-ro 0 1" > ${TARGET}/etc/fstab

chroot ${TARGET} /bin/bash -c "apt clean"

umount ${TARGET}/sys
umount ${TARGET}/proc
umount ${TARGET}/dev/pts
umount ${TARGET}/dev

rm ${TARGET}/linux-image-5.10.1.001+_5.10.1.001+-3_amd64.deb
# 移除 chroot 期间用的 policy-rc.d，避免最终镜像里带着它导致首次启动时服务无法被 init 脚本拉起
rm -f ${TARGET}/usr/sbin/policy-rc.d

if [ "$1" == "--debug" ] || [ "$1" == "-d" ]; then
  TARNAME=ws215i-debian13-rootfs-burn-base-debug.tar.gz
else
  TARNAME=ws215i-debian13-rootfs-burn-base.tar.gz
fi

echo "tar $OUTPUT/$TARNAME"
tar czf $OUTPUT/$TARNAME -C ${TARGET} .
 
echo "done"
