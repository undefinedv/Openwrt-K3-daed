# Phicomm K3 — ImmortalWrt + daed 自动构建

斐讯 K3（BCM4709C0 / bcm53xx / ARM Cortex-A9）固件，GitHub Actions 自动编译。

核心目标是让 **daed** 能在 K3 上跑起来——这需要内核带 BTF，而 OpenWrt 系所有分支默认都不带。

## 基线

| 项 | 值 |
|---|---|
| 源码 | [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-25.12` |
| 内核 | 6.12 |
| 架构 | `arm_cortex-a9` / `bcm53xx/generic` |
| 默认地址 | `192.168.11.1` |

选稳定分支而不是 master：两者的 stable 内核**同为 6.12**，`daed` 版本也同为 `1.27.0`，但稳定分支只收 bugfix，定时构建不会被上游日常改动冲垮。想追 6.18 测试内核的话见文末。

## 固件内容

- **daed** + `luci-app-daed`（eBPF 透明代理）
- **homebox**（网络测速工具箱）
- **kmod-tcp-bbr**
- LuCI + 简体中文
- **常用命令行工具**：`curl` `wget-ssl` `htop` `nano` `bash` `less` `file` `lsof` `findutils` `tar` `gzip` `unzip`
- **网络排查工具**：`ip-full` `tcpdump-mini` `bind-dig` `mtr-json` `ethtool` `socat` `iperf3` `bpftool-minimal`
- **硬件与传输**：`usbutils` `pciutils` `openssh-sftp-server`

busybox 本身已提供绝大多数基础命令，上面只补它没有或功能残缺的。其中 `ip-full`
是刻意加的——busybox 的 `ip` 看不了 tc 规则，而 daed 正是挂在 tc 层，出问题时没它没法查。

> **包名有坑，改配置前务必核对 feed。** 已经踩到过的：`wget` 无此包（只有
> `wget-ssl` / `wget-nossl`）、`mtr` 无此包（只有 `mtr-json` / `mtr-nojson`）、
> `bpftool` 无此包（只有 `bpftool-minimal` / `bpftool-full`）、`zip` 和
> `diffutils` 在 feed 里根本不存在、`coreutils` 是带 `MENU:=1` 的空壳菜单包
> （真正的命令在 `coreutils-*` 子包里）。写错不会报错，`make defconfig`
> 会静默改成 `n`——这正是 workflow 里那道逐条校验存在的原因。

### 为什么没有 TurboACC

不是漏了，是**故意不装**：

| TurboACC 子项 | 原因 |
|---|---|
| Flow Offloading | 与 daed 互斥。daed 把流量重定向到本地 socket，这些包不走 forward 快速路径，offload 对代理流量零收益；对直连流量又会和 eBPF 钩子抢路径。 |
| Shortcut-FE | 高通平台的东西（`simulated-driver` 直接锁了 `@TARGET_qualcommax`）。K3 是 Broadcom，硬件 NAT 加速靠闭源 CTF/FA 驱动，OpenWrt 上没有。纯软件 SFE 绕过 netfilter，与 eBPF 代理冲突更严重。 |
| BBR | **这项有用**，已单独装 `kmod-tcp-bbr`——daed 的出站代理连接都是路由器自己发起的，BBR 正作用在这条链路上。 |

## BTF：daed 的硬性前提

daed 走 eBPF CO-RE，运行时必须能读到 `/sys/kernel/btf/vmlinux`。而 `KERNEL_DEBUG_INFO_BTF` 的 `default y` 列表里只有 armsr / bcm27xx / filogic / rockchip / x86_64 等，**bcm53xx 不在内**，必须手动开：

```
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
```

`KERNEL_DEBUG_INFO_BTF` 会自动 `select DWARVES`（构建 pahole）。

workflow 里有**两道检查**，避免编出"看着成功、实际 daed 起不来"的固件：

1. `make defconfig` 之后校验关键选项没被静默丢弃（依赖不满足时 kconfig 会悄悄改成 n），不通过直接中止，不浪费两小时编译
2. 编译完成后 `readelf -S vmlinux` 确认 `.BTF` 段真的存在

## 刷机后验证

```sh
# 1. BTF 必须存在，否则 daed 会报 "unable to find BTF for kernel"
ls -l /sys/kernel/btf/vmlinux

# 2. 确认 tc/bpf 模块就位
lsmod | grep -E 'sched_bpf|sched_core|veth'

# 3. 启用 BBR
sysctl -w net.ipv4.tcp_congestion_control=bbr

# 4. 建议开启 packet steering（K3 是双核 A9，能改善多核分流；与 daed 不冲突）
uci set network.globals.packet_steering=1 && uci commit network
```

## 已知风险

- **内存**。K3 只有 512MB RAM，daed 加载 geosite/geoip 后常驻约 150–250MB。别再叠第二套代理。
- **CPU**。BCM4709C0 是 2017 年的双核 Cortex-A9 @1.4GHz，代理流量的 TLS 加解密是瓶颈，且 offload 帮不上忙。
- **homebox 版本旧**。`jjm2473/openwrt-apps` 里的包锁在 2020 年的源码（`0.0.0_pre2020062901`），且构建时会 `go get` 联网拉依赖。打包者 2026-02 还在维护该包，大概率能编过；真编不过就把 `.config` 里的 `CONFIG_PACKAGE_luci-app-homebox` 换成 ImmortalWrt 自带的 `CONFIG_PACKAGE_speedtest-go=y` + `CONFIG_PACKAGE_iperf3=y`（维护中，但没有 LuCI 面板）。
- **编译耗时**。开了 `KERNEL_DEBUG_INFO` 生成 DWARF，中间产物比常规编译大得多，workflow 里已加强磁盘清理。
- **BPF 工具链**。`.config` 里用的是 `CONFIG_BPF_TOOLCHAIN_HOST=y`，直接借宿主机的 LLVM 编译 daed 的 eBPF 字节码，省掉自建一整套 LLVM 的 30–60 分钟（ubuntu-24.04 自带 clang 18，满足 `CLANG_MIN_VER:=12`）。若哪天因 clang 版本过新编不过，把这行换成 `CONFIG_BPF_TOOLCHAIN_BUILD_LLVM=y` 让 OpenWrt 自己编——慢，但不挑宿主机。

## 改配置

`.config` 是一份**种子配置**，只写关键选项，其余交给 `make defconfig` 补全——上游改动时不会像 700 行完整 config 那样大面积失效。

要增删软件包：

```sh
git clone --depth 1 https://github.com/immortalwrt/immortalwrt -b openwrt-25.12 openwrt
cd openwrt && ./scripts/feeds update -a && ./scripts/feeds install -a
cp /path/to/this/repo/.config .config
make menuconfig          # 调整
./scripts/diffconfig.sh > /path/to/this/repo/.config   # 导出差异，覆盖回本仓库
```

**不要**直接把 `make defconfig` 生成的完整 `.config` 提交回来。

### 想用 6.18 测试内核

把 workflow 里的 `REPO_BRANCH` 改成 `master`，并在 `.config` 加 `CONFIG_TESTING_KERNEL=y`。注意 bcm53xx 在 6.18 上的驱动（尤其 `brcmfmac` 无线）未经充分验证，K3 上有无线不工作的风险。

## 触发构建

- Actions 页面手动 `Run workflow`（可勾选 `ssh` 开 tmate 会话调试）
- 定时：北京时间每周六 02:37

## 致谢

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)（本仓库的 workflow 基于其改写，MIT）
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [daeuniverse/dae](https://github.com/daeuniverse/dae) / [daed](https://github.com/daeuniverse/daed)
- [XGHeaven/homebox](https://github.com/XGHeaven/homebox) / [jjm2473/openwrt-apps](https://github.com/jjm2473/openwrt-apps)

## License

[MIT](LICENSE) © P3TERX
