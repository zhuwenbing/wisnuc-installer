# wisnuc installer (ws215i / Debian 13)

本项目包含制作 ws215i 设备镜像的工具：

1. ws215i 设备 emmc 上的文件系统（rootfs）
2. 烧录 U 盘

> 本项目由原来的 Ubuntu 16.04 版本改造而来，现已基于 Debian 13 (trixie) 构建，
> 并已移除 prepare-wisnuc 以及 64 位 X86 PC 安装光盘相关内容。

## 运行环境

本项目的运行环境为 Ubuntu/Debian 桌面版（需要 `debootstrap`），在 Debian 13 上开发使用。
制作过程使用了 `chroot`、`mount`、`loop device` 等功能，无法在绝大多数云主机上运行，也无法在 Windows 上直接运行。

```bash
$ sudo apt install debootstrap tree
```

## Quick Start

```bash
# 中华人民共和国境内开发者，执行下面 2 个命令时建议关闭 VPN
$ sudo ./build-rootfs-emmc-base.sh
$ sudo ./build-burn-base.sh
$ sudo ./build-image.sh
```

输出文件位于 output 目录下

```
$ tree output -L 3
output
├── ws215i-debian13-rootfs-burn-base.tar.gz
├── ws215i-debian13-rootfs-emmc-base.tar.gz
└── ws215i-debian13-build-180104-180015.img
```

其中扩展名为 `img` 的文件为镜像文件，可以直接 `dd` 到 U 盘上使用。

## 合成过程

`build-rootfs-emmc-base.sh` 脚本用于生成 ws215i 的 emmc 的 rootfs（基于 Debian 13 的最小 rootfs，不含任何预装应用目录）；

`build-burn-base.sh` 脚本用于生成烧录 U 盘的 rootfs，它是最小化的 Debian，可以在 ws215i 上 boot 和执行自动烧录脚本（`imageburn.sh`），把 emmc rootfs 烧录到板载 emmc 上。

`build-image.sh` 脚本把这些内容组合成可直接 `dd` 的 U 盘镜像：

1. 创建一个临时文件，用 loop device 挂载，然后创建分区和 ext4 文件系统；
2. 展开 burn rootfs (base) 到目标文件系统上；
3. 放入 emmc rootfs 压缩包；
4. 生成最终的镜像文件。

图示如下：

```
build-rootfs-emmc-base.sh           build-burn-base.sh
        |                                |
        v                                v
 output/ws215i-debian13-rootfs-emmc-base.tar.gz
        |                                |
        | build-image.sh                 |
        v                                v
 output/ws215i-debian13-rootfs-emmc-base.tar.gz  +  output/ws215i-debian13-rootfs-burn-base(-debug).tar.gz
                                            |
                                            | build-image.sh
                                            v
                                output/ws215i-debian13-build-180104-171627.img
```

## build-rootfs-emmc-base.sh

该脚本创建 ws215i 的 rootfs (emmc) 压缩包文件，基于 Debian 13 (trixie)。

执行该脚本需要 root 权限（`sudo`）。

过程如下：

1. 创建 `target/emmc` 目录
2. 用 `debootstrap` 在目录下安装 Debian 13 最小基础系统
3. 修改 apt 源为国内镜像
4. 创建如下 systemd unit
   1. firstboot（wisnuc-firstboot）
   2. timesyncd
   3. wired.network
   4. resolv.conf，先放入一个临时版本，在 chroot 最后更新其为生产环境版本
   5. hosts
   6. hostname
5. chroot
   1. 安装 deb 包
   2. 创建 wisnuc 用户，加入 sudo
   3. 安装 ws215i 定制内核并 `apt-mark hold` 防止被升级替换（Debian 13 无 Ubuntu 的 meta 内核包，直接 hold 定制内核包本身）
   4. 使能所有需要的 systemd 服务
   5. 创建 ws215i 启动需要的 boot 文件（包括符号链）
   6. 修改 fstab
6. post-install (leave chroot)
   1. 清理内核 deb 文件
   2. 清理 apt
   3. 更新 resolv.conf (symlink to systemd resolv.conf)
7. 最后把 rootfs 打包成 `output/ws215i-debian13-rootfs-emmc-base.tar.gz`

## build-burn-base.sh

该脚本生成 USB 烧录盘的最小文件系统，USB 烧录盘本身也是一个包含完整 rootfs 的 Debian 运行系统，不只是 ramdisk。其内容和 emmc 镜像相仿，做了裁剪。

该脚本需要 root 权限（`sudo`）。

该脚本接受参数 `--debug`，debug 模式下最终输出的镜像文件会包含 openssh server，方便开发者调试。

```bash
sudo ./build-burn-base.sh            # 生成 output/ws215i-debian13-rootfs-burn-base.tar.gz
sudo ./build-burn-base.sh --debug    # 生成 output/ws215i-debian13-rootfs-burn-base-debug.tar.gz
```

## build-image.sh

该脚本合成上述内容：

1. 创建一个临时文件，用 loop device 挂载，然后创建分区和 ext4 文件系统；
2. 展开 burn rootfs (base) 到目标文件系统上；
3. 装入 emmc rootfs 压缩包；
4. 生成最终的镜像文件。

该脚本需要 root 权限。

该脚本支持 `--debug` 参数。如果提供该参数，会使用 debug 版本的 burn rootfs。

输出文件的命名规则如下：

```bash
# 非 debug 版本
ws215i-debian13-build-${时间戳}.img

# debug 版本
ws215i-debian13-build-${时间戳}-debug.img
```

其中时间戳格式为 `yymmdd-HHMMSS`，例如 `180104-171627`。

## 文件

`assets` 目录下包含：

1. ws215i 的定制内核包（debian 格式），内核版本为 4.3.3
2. 用于烧录的 `imageburn.sh`（把 emmc rootfs 烧录到板载 emmc）
3. apt 的 `sources.list` 文件（Debian 13 trixie，使用国内镜像源）

## 其他问题

1. 该制作过程使用了 chroot，mount，loop device 等功能，无法在绝大多数云主机上运行；
2. 注意 chroot 环境下 resolv.conf 的配置；
3. 因为有 chroot 和装包过程，所以 systemd 官方的 firstboot 服务无法使用，我们自己定义了一个 firstboot service（wisnuc-firstboot）；
4. `debootstrap` 需要联网从 Debian 源拉取基础系统，境内建议配合镜像使用（见 assets/sources.list 中的注释）。
