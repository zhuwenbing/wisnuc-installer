## Intro

本项目面向玩家和开发者。

本项目用于制作闻上 WS215i 设备的 rootfs 和系统烧录 U 盘，基于 Debian 13 (trixie)。

> 本项目由原来的 Ubuntu 16.04 版本改造而来，已移除 prepare-wisnuc 以及 64 位 X86 PC 安装光盘相关内容。

## 准备

本项目的运行环境为 Ubuntu/Debian 桌面版，项目开发者在 Debian 13 上使用。
此项目需要 `debootstrap`。

准备工作包括如下操作：

```bash
# 安装所需命令
$ sudo apt install debootstrap tree

# 下载项目代码
$ git clone https://github.com/wisnuc/wisnuc-installer
$ cd wisnuc-installer
```

## 制作 WS215i 烧录工具

```bash
# 中华人民共和国境内开发者，执行下面 2 个命令时建议关闭 VPN
$ sudo ./build-rootfs-emmc-base.sh
$ sudo ./build-burn-base.sh
$ sudo ./build-image.sh
```

生成的镜像文件位于 `output` 目录下，扩展名为 `img`。

## 说明

1. 该制作过程使用了 chroot，mount，loop device 等功能，无法在绝大多数云主机上运行，也无法在 Windows 上直接运行；
2. `debootstrap` 需要联网从 Debian 源拉取基础系统，境内建议配合国内镜像使用（见 assets/sources.list 中的注释）。
