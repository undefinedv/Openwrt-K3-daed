#!/bin/bash
#
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (在 feeds update 之前执行)
#
# 此处只做 feeds.conf.default 层面的改动。
# 注意：不要在这里整个挂载第三方 feed —— 很多第三方仓库含有与
# ImmortalWrt 官方 feed 同名的包（7zip / zip / fonts / gcompat ...），
# `feeds install -a` 会让后挂载的 feed 覆盖官方包。
# 单个第三方包请放到 diy-part2.sh 里按需提取。
#

# 示例：启用官方 feeds.conf.default 里被注释掉的源
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default
