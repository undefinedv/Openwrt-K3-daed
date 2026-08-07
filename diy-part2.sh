#!/bin/bash
#
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (在 feeds install 之后、defconfig 之前执行)
#
set -e

# ---------------------------------------------------------------------------
# 默认 LAN 地址与主机名
# ---------------------------------------------------------------------------
sed -i 's/192.168.1.1/192.168.11.1/g' package/base-files/files/bin/config_generate

# ---------------------------------------------------------------------------
# homebox 网络测速工具箱
#
# ImmortalWrt 官方 feed 未收录，需从 jjm2473/openwrt-apps 取。
# 该仓库含 30+ 个包，其中 7zip/zip/fonts/gcompat 等与官方 feed 同名，
# 整个挂成 feed 会覆盖官方包，所以这里只提取需要的两个包目录。
# luci-app-homebox/Makefile 里有 `include ../luci-alias.mk`，
# 因此必须保留仓库根目录的 luci-alias.mk 和原有的目录层级。
# ---------------------------------------------------------------------------
HOMEBOX_DIR="package/custom/openwrt-apps"
rm -rf "$HOMEBOX_DIR"
mkdir -p "$(dirname "$HOMEBOX_DIR")"
git clone --depth 1 https://github.com/jjm2473/openwrt-apps.git "$HOMEBOX_DIR"
rm -rf "$HOMEBOX_DIR/.git"

# 只留 homebox 相关，其余目录全部删掉以免与官方 feed 冲突
find "$HOMEBOX_DIR" -maxdepth 1 -mindepth 1 -type d \
	! -name 'homebox' ! -name 'luci-app-homebox' -exec rm -rf {} +

echo "==> package/custom/openwrt-apps 保留内容："
ls -1 "$HOMEBOX_DIR"
