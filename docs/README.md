# Droidspaces / 小米 17 内核适配完整归档

归档整理日期：2026-08-25；公开版整理：2026-09-03（Asia/Shanghai）

公开版当前结论：`r30-stock-containers` 的 User Namespace 候选已在一台 Xiaomi 17
`pudding` 测试设备上完成启动和 `unshare -Ur` smoke test。当前分支对应实际刷入的
HyperOS 4.0.0.9 卡刷包；本文其余章节保留历史实验时间线。旧候选的 fastboot/AVB 限制
不应被误读为当前公开仓库包含可直接刷写的镜像。

本文是本项目唯一保留的技术文档，合并了 2026-08-21 至 2026-08-24 的构建、打包、KernelSU 配对、KMI/CRC 审计、实机启动、Wi-Fi/RFKILL、蜂窝/IMS 排查和设备恢复记录，并补充了 2026-08-26 的当前完整字库、小米公开源码依赖审计、第三方 Droidspaces 补丁路线和非官方 BL 解锁链信息。

本文保留足以复现实验判断、识别历史产物和继续研究的技术信息，但删除重复工作日志。历史源码、构建目录、候选镜像、设备日志、bugreport 和旧报告均已删除；文中的旧路径与候选哈希只用于识别证据，不表示文件仍然存在，更不能据此直接刷写。

## 1. 最终结论与证据优先级

### 1.1 最终结论

- 设备为小米 17，型号 `25113PN0EC`，代号 `pudding`，平台 `Qualcomm SM8850 / canoe`；用户态为 Android 17 / HyperOS 4，内核基线属于 `android16-6` GKI 6.12.69。
- 最近一次可观测实机状态是通过 `fastboot boot` 临时运行首版 R30 stock-containers 候选，活动槽为 A；`boot_a` 与 `init_boot_a` 均未在本轮写入。
- slot B 的 `boot_b`、`init_boot_b`、`vendor_boot_b`、`dtbo_b` 备份均为全零，不是可用备用系统；整个项目不使用 slot B。
- 本地 Kleaf/Bazel 构建链、原厂导出 CRC 恢复、`vendor_data_pad` 1024-byte/KABI 兼容机制、466 个 vendor module 和 103 个 stock system_dlkm consumer 的联合审计均已建立。
- R62 自定义内核成功编译，466 个 vendor module 静态审计达到 0 mismatch、0 missing、0 unexported、0 provider conflict。
- 用户实机确认 R62 能进入系统，相机、指纹、Wi-Fi 和蓝牙可用，但该历史样本无法建立移动数据、IMS 注册和双卡通话。
- 2026-08-27 的 R30 stock-compat 最终候选同时完成 release identity 与 stock module signing certificate 配对；运行模块数从失败候选的 579 恢复到 stock 的 670。
- 自动验收确认 Wi-Fi、蓝牙、双卡语音/数据注册、两路 IMS 网络和蜂窝 Internet 网络均恢复；用户随后确认“现在好像所有东西都能用”。
- 首版容器候选已实机完成 Android 启动和 PID/IPC namespace、SYSVIPC、mqueue、devtmpfs smoke test，但只加载 669/670 个 stock 模块；唯一缺少的 `rust_binder.ko` 暴露出此前 466 模块审查没有覆盖 stock system_dlkm consumer 的缺口。
- 修复后构建把新增 SYSVIPC C 布局对 bindgen 隔离；相对 stock-compatible 基线只新增 `init_ipc_ns`、`put_ipc_ns` 两个导出，旧符号零删除、零 CRC 变化。stock `rust_binder.ko` 的 234 个导入全部静态匹配，随后实机模块数恢复到 670，`rust_binder` 正常加载。
- 历史 R62 的 `dsi_init_cb` 分叉仍是有效旧证据，但不再代表当前 R30 stock-compat 候选的运行结果。
- 唯一一次“最小 RFKILL 自定义内核下电话打通”的实验后来确认实际运行的是 stock Image，结论已撤回。
- 当前已有可作为后续容器配置基线的临时启动候选，但修改 kernel 后没有有效 Xiaomi AVB 签名，仍不能直接 flash 或视为长期安装包。

### 1.2 历史状态裁决规则

原始资料是连续追加的工程日志，许多“当前结论”只适用于当时阶段。本文按以下优先级裁决冲突：

1. 日期更晚、证据更直接的实机结果覆盖早期推测。
2. 实际解包出的 Image、运行时 kallsyms、pstore、dmesg、RIL/radio logcat 高于文件名和目录名。
3. SHA-256 高于 `latest`、`final`、`out/Image` 等可被覆盖的路径描述。
4. stock 对照与自定义样本必须使用同一业务判据。
5. 静态 KMI/CRC 审计只证明其覆盖范围内的符号兼容，不自动证明启动、system_dlkm、Framework、Wi-Fi、IMS 或通话正常。

由此，2026-08-22 文档中“RFKILL v5 尚未实机测试”的状态已被 2026-08-23 长测覆盖；对 R00/C0/v5 的判断又被 2026-08-24 的 R62 构建与实机对照进一步修正。

## 2. 当前设备与原始备份

### 2.1 最后确认的设备状态

| 项目 | 最后确认值 |
|---|---|
| 设备 | 小米 17 |
| 型号 / 代号 | `25113PN0EC` / `pudding` |
| SoC / 平台 | Qualcomm SM8850 / `canoe` |
| 系统 | Android 17 / HyperOS 4.0.0.9.XPCCNXM.D00（卡刷包） |
| 活动槽位 | `_a` |
| stock kernel release | `6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k` |
| stock boot 内 Image SHA-256 | `574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2` |
| `boot_a` SHA-256 | `af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b` |
| `init_boot_a` SHA-256 | `bc9bc4d84a03b41f2ce159ff423ccaf12fcef2badc3d94fbb4e84d2e5bdf6310` |
| 最初 KernelSU LKM SHA-256 | `fb51781a37c96c29cfd95b5a4b6160c8cb6410bcb027d0beec19d63ddd9f7f39` |
| SELinux | Enforcing |
| Root | KernelSU 可用；历史核验 context 为 `u:r:ksu:s0` |
| Android | `sys.boot_completed=1` |

2026-08-24 stock 对照确认：两张 SIM 均完成 IMS 呼叫；关闭 Wi-Fi 后移动数据稳定使用 `rmnet_data2`；modem remoteproc、qcrild 和 IMS daemon 正常运行；`libarc4`、`mac80211`、`cfg80211`、`wwan` 能正常配合。

### 2.2 历史小备份

历史小备份目录（该目录后来已删除，内容已被 2026-08-26 当前完整字库覆盖）：

`../droidspaces-device-backup-20260821-212408/`

它当时包含 A/B 槽 `boot`、`init_boot`、`vendor_boot`、`dtbo`、`vbmeta`，以及 `getprop.txt`、`uname.txt`、`kernel.config.gz`、两份 KernelSU 模块备份和 `magiskboot`。

2026-08-25 已从现存备份重新验证 16 个文件的 SHA-256，全部通过，清单见第 16 节。

### 2.3 slot B 不是回退槽

~~~text
boot_b.img        all-zero
init_boot_b.img   all-zero
vendor_boot_b.img all-zero
dtbo_b.img        all-zero
~~~

不得使用“安装到未使用槽位”、不得切换 active slot 到 B，也不得把 B 槽视为 A 槽失败后的自动回退。所有恢复能力依赖 A 槽原始备份、USB/fastboot 可进入性和主机端校验。

### 2.4 分区操作事实

- 最早的错误 boot 曾被写入 `boot_a`，随后用原始 `boot_a` 恢复；用户数据未清除。
- 早期 exact KernelSU 与 RFKILL v5 测试曾临时写入测试用 `init_boot_a`，每次结束后均恢复最初 KernelSU 基线并整分区回读校验。
- 2026-08-24 R62 测试只使用 `fastboot boot` 临时启动，没有写入 `boot_a` 或 `init_boot_a`。

最终分区哈希证明临时变化均已撤销，当前不需要重复刷写恢复镜像。

### 2.5 2026-08-26 当前完整字库

当前升级后系统的完整备份位于：

`backup/字库备份_1787746457069/`

只读检查结果：

| 项目 | 结果 |
|---|---|
| 顶层文件 | 162 个 |
| 总大小 | 16,577,852,702 bytes，约 15.439 GiB |
| `slot.txt` | `a` |
| `super.img` 大小 | 13,421,772,800 bytes |
| `super.img` SHA-256 | `bb700418093063e188f6835659aa2526b5a064ffa2e9eef5eb5c41b5d6a514ed` |

当前完整字库中的 A 槽核心启动镜像与第 2.1 节历史基线一致：

~~~text
af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b  boot_a.img
bc9bc4d84a03b41f2ce159ff423ccaf12fcef2badc3d94fbb4e84d2e5bdf6310  init_boot_a.img
54a2e92fadcd28dd77a90aaf6fdb61e920f6f4913bb7597cedf0714350dee4c7  vendor_boot_a.img
1fe1bbb950c9b4f004814ccee079292b0cced1945719014e7f700ca30a6a2cfc  dtbo_a.img
2abe2d9a355ca4db21bb29f980d7ce19310cab7be849b089d9e5f6a9896433db  vbmeta_a.img
~~~

该备份还包含 `super`、A/B 槽启动链、modem/modemfirmware、DSP、蓝牙固件、`persist`、`fsg`、`modemst1/2`、ABL/XBL/UEFI 和大量设备唯一分区镜像。它现在是内核开发、模块审计和恢复研究的主基线。

安全边界：

- `flashAll.bat` 会顺序写入大量启动、安全、基带和设备唯一分区，**不得把它当作普通恢复脚本执行**。
- `persist`、`fsg`、`modemst1/2`、校准和 NV 数据只能用于本机，严禁公开或使用其他设备的镜像替换。
- `md5.txt` 是备份工具生成的清单；目前本文只记录已独立复算的关键 SHA-256，不把未复算条目写成已验证。
- 普通分区字库不能视为 RPMB、eFuse/QFPROM、TEE 内部状态或硬件 rollback index 的备份。

## 3. 项目目标与技术约束

### 3.1 Droidspaces 所需能力

原始内核检查缺少或关闭：

~~~text
CONFIG_PID_NS
CONFIG_IPC_NS
CONFIG_SYSVIPC=n
CONFIG_POSIX_MQUEUE=n
CONFIG_DEVTMPFS=n
CONFIG_USER_NS=n
CONFIG_CGROUP_DEVICE=n
~~~

本项目采用最小功能增量，目标启用：

~~~text
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_DEVTMPFS=y
~~~

`CONFIG_USER_NS` 与 `CONFIG_CGROUP_DEVICE` 不是本轮 Droidspaces 的必要条件，保持关闭以缩小差异面。

### 3.2 GKI 环境约束

小米 17 使用 GKI 架构：通用内核 Image 与 vendor/system_dlkm 模块分离。只替换 boot 中 kernel，必须继续兼容：

- `vendor_boot`、`vendor_dlkm`、`system_dlkm`；
- 466 个已提取 vendor module；
- Qualcomm/Xiaomi 用户态服务和 HAL；
- KernelSU init_boot 组合。

原厂重要属性：

~~~text
ARM64, 4K page
CONFIG_MODVERSIONS=y
CONFIG_GENDWARFKSYMS=y
CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024
android_arch_task_struct_size=1024
boot image header v4
~~~

因此“能编译”只是第一层，之后必须分别验证 boot/AVB、KernelSU、vendor CRC、system_dlkm 加载、无线、显示、存储、蜂窝和 Framework 初始化。

## 4. 2026-08-21：R00、AVB 和 KernelSU 阶段

### 4.1 第一版 R00 构建和 flash 失败

初始源码：

~~~text
Android Common commit: b18aa09ef8e78438227d33ab5e938145332e0e03
tag: android16-6.12.69_r00
Clang: Android r536225 / 19.0.1
~~~

应用 Droidspaces 官方 6.12 SYSVIPC KABI 补丁，启用最小配置。

该补丁当时归档的 SHA-256 为：

`059db74ecf615273785f25c54b0b26f61cee9ea330d3b4787cdfd8172778eaad`

| 产物 | SHA-256 | 结论 |
|---|---|---|
| 初版 Image | `43ef3165502d30ac5d346f235db11e634c2082725d8539df8afe75f50d4ba21c` | 能编译，不代表兼容 |
| 初版 boot | `adaf8d8b83c794e56b680990183fcb4b0ce1bd034c6dd16c2375a098a4378d36` | 丢失 AVB，禁用 |

初版 boot 写入 `boot_a` 后 bootloader 报：

~~~text
Slot _a is unbootable, trying alternate slot
FindBootableSlot() status: Load Error
LoadImageAndAuth failed: Load Error
error_type=901005101
~~~

自制镜像不含原始 boot 的 `AVB0` 和末尾 `AVBf`，因此失败发生在 Linux 获得执行权之前，不能用于判断 Droidspaces 配置或内核代码。随后原始 `boot_a` 被恢复，用户数据未清除。

### 4.2 MagiskBoot 与 AVB 边界

以 stock boot 为模板进行 MagiskBoot 解包/重打包：无修改重打包可保留部分 AVB 外形；替换 Image 后仍有 `AVB0`/`AVBf`，但 descriptor 继续声明原始 payload size/digest，`magiskboot verify` 失败。`magiskboot sign` 生成 `AVB1_SIGNED`，不是 Xiaomi 原厂 AVB 2.0 信任链的替代。

原始 `vbmeta_a` 使用链式信任并固定 boot 公钥：

~~~text
boot public key SHA-1: 8256e695b81d1eb6dd0b1ce5d08b9c73cbb5e5b6
~~~

项目没有 Xiaomi 私钥，不能为修改 payload 生成等价原厂签名。因此：

> 保留 AVB 外形不等于 AVB 验证有效。所有替换 kernel 的候选只能用于 `fastboot boot` 临时测试，不能直接 flash。

### 4.3 通用 KernelSU panic

一个 MagiskBoot 模板候选被接受，pstore 确认自定义内核实际运行：

~~~text
Linux version 6.12.69-android16-6-4k (builder@host)
~~~

约 0.44 秒后发生：

~~~text
kernelsu: no symbol version for module_layout
Unable to handle kernel NULL pointer dereference
pc : ksu_dup_sepolicy+0x2c/0x218 [kernelsu]
Kernel panic - not syncing: Oops: Fatal exception
~~~

原始 `init_boot_a` 中 KernelSU：

~~~text
KernelSU/ksud: v3.2.5
vermagic: 6.12.76-4k-gae4e2f4f997e-dirty
SHA-256: fb51781a37c96c29cfd95b5a4b6160c8cb6410bcb027d0beec19d63ddd9f7f39
Build ID: 273df1499dab070dd2aded84248ac6981d073e48
~~~

空 `__versions` 是 KernelSU 手工 kallsyms 重定位流程的设计，不是单独错误；真正问题是该模块与本轮 6.12.69 内核不精确匹配。

### 4.4 exact KernelSU 成功，vendor CRC 暴露

使用 KernelSU commit `b0bc817b4e966aa6aa830834eaf6ef765d821d40`，基于精确内核源码、生成头文件和 vmlinux 重编：

| 产物 | SHA-256 |
|---|---|
| early exact LKM | `189fd153c4b2a101d8bd0e6e7cb48909fdb539434249638db6c6bec21346ca86` |
| early exact init_boot | `b9785969d7bd20b068a644e2488e5065c81f77692ae8dd34f847cdd00ca0bb6b` |

218 个 undefined symbol 均在同一 vmlinux 找到，`check_symbol` 返回成功；实机 pstore 显示 KernelSU 加载并进入 `init.real`，没有再次出现 `ksu_dup_sepolicy` panic。

但 Android init 批量加载 Xiaomi 模块失败：

~~~text
spmi_pmic_arb: disagrees about version of symbol module_layout
init: Failed to insmod ...: Exec format error
~~~

同类错误涉及 `unfairmem`、`scene_swappiness`、`rtc_pm8xxx`、`qti_regmap_debugfs`、`qseecom_proxy`、`qnoc_qos` 等，随后显示、电源、存储和 SoC 组件 deferred probe，设备黑屏。

这直接推翻“release/vermagic 主字符串相同就足够兼容 vendor module”。

## 5. 2026-08-22：Kleaf、KABI 与 boot-first

### 5.1 本地化构建路线

公开 `popsicle-w-oss` 不是完整内核基线：其 `android/ACK_SHA` 指向 `android16-6.12-2025-06_r8 / 6.12.23`，`BUILD.bazel` 和 `common_sources.bzl` 依赖外部 `//common`，Qualcomm datarmnet/dataipa 也不在 checkout 内。因此它只能作为 pudding/canoe DDK target、配置与模块依赖参考。

项目随后建立本地 Android Common + Kleaf/Bazel 工作流，覆盖：

- Droidspaces patch 与 defconfig fragment；
- Image、vmlinux、Module.symvers、vmlinux.symvers；
- 原厂 Image 重建和导出 CRC 恢复；
- 466 个 vendor module 全量导入审计；
- boot v4 重打包与结构检查。

第一次 Kleaf 成功产物：

~~~text
Image SHA-256: 3316ed92b2fc58d5dcee1d39e0c9a30179e38c9ede339461472eaf3d9b18ebc0
kernel.release: 6.12.69-android16-6-maybe-dirty-4k
Image size: 41896448 bytes
~~~

Rust Binder 构建曾因 `put_ipc_ns` 未导出失败，随后只增加最小 `EXPORT_SYMBOL(put_ipc_ns)`，构建通过。

### 5.2 vendor_data_pad 的 1024-byte/CRC 双重约束

原厂配置与 boot 参数均要求：

~~~text
CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024
android_arch_task_struct_size=1024
~~~

从 stock Image 重建 ELF 后直接测得 `vendor_data_pad` 地址跨度为 `0x400`，即 1024 bytes。

从原厂 `__ksymtab*` 与 `__kcrctab*` 平行数组恢复导出表：

~~~text
ordinary exports: 3649
GPL exports:      6221
total exports:    9870
vendor_data_pad CRC: 0xf54e5881
~~~

纯 AOSP 直接把数组从 512 改为 1024 会生成 CRC `0xa4519653`，造成 11 个确定 mismatch：

~~~text
cpu_mpam.ko
hung_task_enh.ko
mi_game.ko
minidump.ko
os_cpu_qi.ko
os_cpu_qs.ko
perf_helper.ko
plat_common.ko
rtg.ko
sched-walt.ko
vip_sched.ko
~~~

失败对照 Image：`a1ed59b699c09de08d69a887020f03f0cc7f119af7efd585c6dbbcbd59bf48d3`。

最终使用 Android Common 正式的 `ANDROID_KABI_TYPE_STRING` 与 stable `gendwarfksyms`：实际对象仍由 Kconfig 分配 1024 bytes，对外公开类型字符串维持 64 个 `u64`，恢复 CRC `0xf54e5881`。

成功产物：

~~~text
Image SHA-256: abc0098ff27ae4c587102f4758b3010b0221b93d4d278b840289a2609737c97c
actual vendor_data_pad size = 1024
published module CRC        = 0xf54e5881
~~~

该方案没有关闭 `CONFIG_MODVERSIONS`、没有硬写 CRC，也没有绕过模块加载检查。

### 5.3 早期 8+20 项与后续闭合

在 `task1024 + KABI rule` 阶段，11 个 CRC mismatch 已归零，但仍有 8 个 `present-but-unexported` 和 20 个 provider 缺失项，涉及 `arm_smmu.ko`、`cpq.ko`、`mi_extent_pool.ko`、`mi_reclaim.ko` 及 swap、CMA、direct reclaim、dma-heap、filemap、superblock、remove-mapping 路径。

这些是有效的历史阶段阻断，但不是最终 bootfirst 失败解释。后续 boot-first/stamped 审计把 mismatch、unexported 和 absent 全部归零，不能再把旧“28 项”当作最终根因。

### 5.4 bootfirst-v1：镜像被接受但中途重启

| 产物 | SHA-256 |
|---|---|
| 输入 Image | `4310a9fee5e834742a7d05b78e5cca7cbc4bfc8fd9d0dc71dcd235e8f220bf97` |
| boot candidate | `9256c3892a1e28bcd0c3c6257c9a0d84ef7093547e12c9f6651539c05df446c9` |

candidate 使用原始 `boot_a` 模板只替换 kernel；重新解包确认内嵌 kernel 与输入 Image 完全一致。

| 结构 | 原始 boot | bootfirst-v1 |
|---|---:|---:|
| `ANDROID!` | 1 | 1 |
| `AVB0` | 3 | 1 |
| `AVBf` | 1 | 1 |
| 镜像大小 | 100663296 | 100663296 |

实机步骤：校验 A 槽分区；临时写入 exact KernelSU init_boot；`fastboot boot`；bootloader 接受；手机进入小米 Logo 中段，闪屏后重启；恢复最初 init_boot 后 stock 达到 `sys.boot_completed=1`。

记录：

~~~text
kernel_panic,null,1787409159 -> 2026-08-22 22:32:39 +0800
bootloader,1787409248        -> 2026-08-22 22:34:08 +0800 左右
mqsas bootmonitor            -> ZYGOTE_FAIL
~~~

恢复后的 dmesg/logcat 主要属于 stock，不能当作 custom runtime 完整日志；pstore 也未形成可清晰引用的完整 panic call trace。此轮只证明镜像已被接受并推进到 Linux/Android 启动中段。

### 5.5 stock identity stamping

bootfirst-v1 的 release/time：

~~~text
6.12.69-android16-6-maybe-dirty-4k
Thu Jan 1 00:00:00 UTC 1970
~~~

通过 `workspace_status.json` 与 Kleaf stamping：

~~~json
{
  "SCMVERSION": "-gb1493ec68d4a-abogki514973465",
  "SOURCE_DATE_EPOCH": 1779287194
}
~~~

构建参数加入：

~~~text
--extra_git_project=common
--config=stamp
~~~

修正产物：

~~~text
Image SHA-256: c60b4cf2fc6ed6331677362f970305d24d1340476bce8afe912587ef959af74b
kernel.release: 6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
build time: Wed May 20 14:26:34 UTC 2026
~~~

312 个本地模块 unique vermagic 为 1，bad vermagic 为 0；466-module stamped 审计全绿。

stamping 修复 `uname -r`、firmware path、构建时间和身份可辨识性，但不能把 R00 代码变成 Xiaomi stock，也不能替代 CRC 或运行时验证。

## 6. Vendor module CRC/KMI 审计

### 6.1 审计范围

主要审计覆盖：

~~~text
vendor modules discovered: 466
vendor modules parsed:     466
parse errors:              0
vendor exported symbols:   3000
~~~

分类包括 vmlinux provider、vendor-internal provider、GKI/system_dlkm fallback、存在但未导出、provider 缺失和 CRC mismatch。

### 6.2 审计演进

| 阶段 | vmlinux match | mismatch | vendor match | GKI fallback | 未导出 | 缺失 | 结论 |
|---|---:|---:|---:|---:|---:|---:|---|
| 历史 baseline | 19278 | 0 | 3159 | 9 | 8 | 20 | CRC 已匹配，provider 不闭合 |
| 直接 task1024 | 19267 | 11 | 3159 | 9 | 8 | 20 | vendor_data_pad CRC 失败 |
| task1024 + KABI rule | 19278 | 0 | 3159 | 9 | 8 | 20 | 11 mismatch 清零 |
| stock + GKI fallback 自检 | 19306 | 0 | 3159 | 9 | 0 | 0 | 审计工具链闭合 |
| stamped / bootfirst | 19306 | 0 | 3159 | 9 | 0 | 0 | R00 后期静态全绿 |
| RFKILL builtin | 19313 | 0 | 3159 | 2 | 0 | 0 | 7 个 RFKILL import 转入 vmlinux |
| R62 final | 19313 | 0 | 3159 | 2 | 0 | 0 | 466 vendor module 静态全绿 |

### 6.3 最终 R62 数字

~~~text
new Module.symvers symbols: 10402
new vmlinux.symvers symbols: 9936
new_vmlinux_match: 19313
new_vmlinux_mismatch: 0
vendor_internal_match: 3159
vendor_internal_mismatch: 0
new_gki_fallback_match: 2
new_gki_fallback_mismatch: 0
vendor_provider_conflict: 0
present-but-unexported: 0
absent_from_new_build_and_audit_set: 0
~~~

重点模块 `arm_smmu.ko`、`binder_gki.ko`、`dwc3-msm.ko`、`msm_drm.ko`、`qcom-scm.ko`、`qcom_q6v5.ko`、`ufs-qcom.ko` 均无 selected-provider mismatch 或 missing。

### 6.4 能力边界

最终 R62 实机仍失败，说明该审计没有覆盖：

- stock system_dlkm/GKI 的完整模块集合；
- 真实 `modules.load`/`modules.dep` 顺序和按需加载；
- KernelSU/init_boot 实际配对；
- vendor service、HAL、NICM/DSI readiness；
- Xiaomi 专有调度、UFS/F2FS、I/O、页面分配扩展的运行时语义。

准确措辞只能是“已审计的 466 个 vendor module 静态符号关系通过”，不能写成“设备兼容通过”。

## 7. Kernel identity、vermagic 与 KernelSU

### 7.1 三个概念

| 层次 | 作用 | 是否能替代 CRC |
|---|---|---|
| `kernel.release` / `uname -r` | 身份、模块/固件路径、系统判断 | 不能 |
| module vermagic | release、SMP、preempt、modversions、架构 | 不能 |
| symbol CRC | 导出符号 ABI 指纹 | `CONFIG_MODVERSIONS` 下核心检查 |
| 实际代码/数据布局 | 运行时语义 | 任何文本不能替代 |

带 CRC 的模块中，`same_magic()` 会跳过 vermagic 第一个空格前的 release 字段，再比较其余 flags。因此 `-maybe-dirty` 不是已证明的 CRC 核心阻断；它主要影响 provenance、日志辨识和固件路径。完整 stock identity 对系统侧仍有实际意义，但 R00 stamp 成 stock 名字也不会变成 R62 或 Xiaomi 内部源码。

### 7.2 KernelSU 结论

- 最初 KernelSU LKM 对 stock 正常，对早期 custom kernel 触发 `ksu_dup_sepolicy` panic。
- 基于精确内核输出重编的 exact LKM 能加载并进入 `init.real`，消除该 panic。
- RFKILL v5 与 R62 都生成过对应 exact LKM；验证包括空 `__versions`、无 extended modversion sections、strip 前后 `check_symbol`。
- C0 后期设备上使用过的 `init_boot_a-ksu-exact-stamped-v2.img` SHA-256 为 `02b5fc859d18be9ec583aa5c6f50fd22390b1942ec2479ff63ef7ed56545ed36`；最终已恢复移除。
- 每个候选必须使用同一构建输出的 exact LKM，或先做无 KernelSU 对照；不能因为 vermagic 相似沿用旧模块。
- init_boot 修改必须独立解包核对条目、模块 SHA、模式、属主和镜像大小。

## 8. Wi-Fi/RFKILL 与 2026-08-23 v5 长测

### 8.1 RFKILL 故障和静态修复

stock-identity R00/C0 自定义内核能够进入 Android/ADB，但 Wi-Fi 无法开启、热点报错。现场证据：

~~~text
CONFIG_RFKILL=m
  + 原厂 rfkill.ko 无法通过自定义内核模块签名保护链
  -> cfg80211 依赖失败
  -> QCA WLAN / nl80211 初始化延迟或失败
  -> Android Nl80211Native early init 保存为 false
~~~

手工补加载后内核侧 `iw wlan0 info` / `iw phy phy0 info` 可工作，但 Framework 不会仅靠 toggle 重跑完整初始化。

修复：

~~~text
CONFIG_RFKILL=y
CONFIG_RFKILL_LEDS=y
~~~

并从 GKI module artifact 列表移除 `net/rfkill/rfkill.ko`。

RFKILL 产物：

| 产物 | SHA-256 |
|---|---|
| builtin Image | `5058091217e6b24d131a5ad78b37120d91255ee4427698d71751c24fe01c46bf` |
| v5 boot | `690b0dad61215f163a709f13e941ede976acf87631ddf6f0f660c4e5d68fe53f` |

7 个 rfkill 符号改由 vmlinux 导出，并保持 CRC：

| 符号 | CRC |
|---|---|
| `rfkill_alloc` | `0x61bef569` |
| `rfkill_blocked` | `0x4375b6f4` |
| `rfkill_destroy` | `0x3614223e` |
| `rfkill_register` | `0x9e7d3016` |
| `rfkill_resume_polling` | `0x3614223e` |
| `rfkill_set_hw_state_reason` | `0x5f1d7600` |
| `rfkill_unregister` | `0x3614223e` |

旧 system_dlkm `modules.load` 仍列出 `rfkill.ko`。对设备 `init.real` 静态反汇编确认 Android libmodprobe 把 `finit_module` 的 EEXIST（errno 17）视为成功路径，因此只为 RFKILL 内建不需要修改 system_dlkm。该结论只排除 EEXIST 阻断风险。

### 8.2 v5 exact KernelSU 与实机结果

RFKILL v5 配套：

| 产物 | SHA-256 |
|---|---|
| exact KernelSU LKM | `a01a92f98dd4410d8959c502ad10377f116cf0dd837676fa243d3be83843ad21` |
| exact init_boot | `4643e9b700a0a5abeb5425e46c40cf7739bb471cabcda70b0436bd5f5433ef88` |
| vmlinux | `52fc3a0469a9bb206a25d205cf09afc695d46281f2826fb39bf904ac9e1e8282` |

init_boot 离线比较确认条目集合和顺序不变，除 `kernelsu.ko` 外其他内容不变，镜像保持 8 MiB；其 AVB descriptor 仍不匹配修改后 payload，不能写成 AVB 验证通过。

2026-08-23 v5 长测：

- Wi-Fi、蓝牙和热点基础链路可用；
- 两张 SIM 的 IMS 与语音仍有严重回归；
- 卡 1 呼叫快速失败；
- 卡 2 RIL 接收 `DIAL [PHONE1]`，`GET_CURRENT_CALLS` 一直为 `DIALING`，未进入 `ALERTING/ACTIVE`；
- 卡 1 短信连续返回 `SMS_FAIL_RETRY`；
- 卡 2 非 IMS SMS 成功，messageRef=73；
- 两张卡反复出现 IMS 4001/4002；
- bugreport SHA-256：`36aa53f496513ee19b865ac3b1496c256d0a17556b038cba084170a0196278c5`。

v5 最终判定：**Wi-Fi/RFKILL 修复通过，蜂窝语音、IMS 和数据失败。**

### 8.3 SIM 映射与 stock IMS 对照

| 用户称呼 | slot | phoneId | subId | 运营商 |
|---|---:|---:|---:|---|
| 卡 1 | 0 | 0 | 2 | 中国电信 |
| 卡 2 | 1 | 1 | 1 | 中国联通 |

历史默认语音和短信为 subId 2，默认数据为 subId 1。stock 启动早期也会短暂出现 IMS 4001/4002，但随后能恢复：

- phoneId 1：20:34:24.608 出现 4002，20:34:25.134 出现 4001，20:34:26.007–20:34:26.008 进入 `onImsConnected / handleImsRegistered`；
- phoneId 0：20:34:36.716 出现 4002，20:34:37.538 出现 4001，20:34:38.819 完成 IMS registered；
- 后续两个槽位的 MMTEL 均达到 `READY`，default 与 IMS APN 都返回 `cause=NONE`，取得 rmnet 接口、DNS、网关和 P-CSCF。

所以 4001/4002 本身不是 v5 特异根因；关键差异是 stock 随后完成 bearer 与 IMS 注册，而 C0/v5 持续失败。

### 8.4 v5 的 framework 注入污染

v5 在 2026-08-23 20:00:08.281 出现一次 `system_server SIGABRT`，abort message 为 `Failed to recognize implicit suspend check`，栈进入 `com.v7878.vmtools.g.c`。设备侧确认该代码来自 HMA-OSS Zygisk；当时还启用了 LSPosed 和 Zygisk Next。随后 `system_server` 重启，并出现 `EVENT_RADIO_NOT_AVAILABLE` 与大量 `OEM_DCFAILCAUSE_4`。

这次崩溃污染并恶化了 v5 样本，但不是蜂窝共同根因：没有发现同类 framework 崩溃的 C0 仍持续出现 IMS 注册和 bearer 失败。

## 9. R00/C0/v5 不是 RFKILL 单变量：R62 基线纠正

C0 与 v5 都基于 `android16-6.12.69_r00 / b18aa09ef`，再用 identity stamp 标成 stock release，所以不能描述为“stock 只修改 RFKILL”。

与 stock 6.12.69 对应的公开 ACK release family：

~~~text
tag: android16-6.12-2026-03_r62
common commit: e2b8ca7c8d0551a6124b1a7322f5ae532845f1b5
official CI build: 16064883
~~~

R00 到 R62 有 443 个文件变化、36,869 行新增和 5,063 行删除，涉及调度、内存管理、Binder、网络核心和 Android vendor hook。

旧兼容提交曾加入 18 个只有 `void *unused` 的占位 hook；R62 已包含真实参数、tracepoint 导出和调用点，覆盖 dma-heap、CMA、compaction、swap、direct reclaim、filemap、superblock 和 remove-mapping 等路径。后续 R62 构建没有继续移植这些占位实现。

R62 还正式包含或提供：`CONFIG_ANDROID_WRAPFD` 与 `drivers/android/wrapfd.c`、`CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024`、BBR/advanced TCP、`prep_new_page` 等 KMI symbol list 所需导出以及 ARM64 erratum 4311569 实现。`popsicle-w-oss` 只作为 DDK/模块依赖参考。

## 10. 2026-08-24：R62 离线构建

### 10.1 构建基线

| 项目 | 值 |
|---|---|
| GKI tag | `android16-6.12-2026-03_r62` |
| common commit | `e2b8ca7c8d0551a6124b1a7322f5ae532845f1b5` |
| CI build | `16064883` |
| Kleaf/kernel build | `a71b075c1d43d226779d2e834433e7a1d1885beb` |
| Clang | `r536225` / Android build `12833971` |
| LLVM commit | `b3a530ec6537146650e42be89f1089e9a3588460` |
| Bazel | `8.0.0` |
| KernelSU commit | `b0bc817b4e966aa6aa830834eaf6ef765d821d40` |

### 10.2 最小改动

~~~text
CONFIG_PID_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IPC_NS=y
CONFIG_DEVTMPFS=y
CONFIG_RFKILL=y
CONFIG_ARM64_ERRATUM_4311569=y
~~~

此外：`sysvsem/sysvshm` 放入 `sched_entity` 前既有 KABI hole；导出 `init_ipc_ns` 与 `put_ipc_ns`；RFKILL 内建后移除 `rfkill.ko` artifact；不移植 18 个旧占位 hook。

### 10.3 构建结果

~~~text
940 actions, 957.531 seconds
cache rebuild byte-identical
release: 6.12.69-android16-6-ge2b8ca7c8d05-dirty-4k
Image size: 42,301,952 bytes
Image SHA-256: da72f40c1ff02d8fc84322b43b2d23fc6f2bf66fd66157ffbb8275a7f6ccf5a4
vmlinux SHA-256: 6cfcaca6f6dfdd7a057f18a89174a7559ecce8801c1a88a93e2a2db1042762b9
KernelSU LKM SHA-256: 088256249924694a53b9592e607fff27a44caefeeeb734097b15d3f1cb9745bd
~~~

`task_struct` 总大小 5,184 bytes：`rt_priority` offset 160，`sysvsem` 164，`sysvshm` 172，`sched_entity` 192。SYSVIPC 字段没有移动既有 `sched_entity`，没有证据支持“公共字段整体偏移”。

## 11. R62 实机测试与蜂窝故障边界

### 11.1 测试安全状态

2026-08-24 通过 `fastboot boot` 临时启动 R62，观察约 14 分 56 秒；没有把 R62 写入 `boot_a` 或 `init_boot_a`，没有使用 slot B。测试后恢复 stock，校验仍为：

~~~text
boot_a      af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b
init_boot_a bc9bc4d84a03b41f2ce159ff423ccaf12fcef2badc3d94fbb4e84d2e5bdf6310
~~~

但该轮不是纯净配对测试：沿用了原 init_boot 的 KernelSU LKM，没有使用为 R62 构建的 exact LKM，system_dlkm/GKI 也没有完整配对；Zygisk、LSPosed、HMA、HyperCeiler、`com.huaMax` 注入仍开启。

### 11.2 第一轮 R62：模块配对缺口

第一轮实际 release：

`6.12.69-android16-6-ge2b8ca7c8d05-dirty-4k`

直接错误：

~~~text
[2.130161] mac80211: Unknown symbol arc4_setkey (err -2)
[2.130179] mac80211: Unknown symbol arc4_crypt (err -2)
~~~

R62 运行模块数为 584，stock 为 670，相差 86；不能把全部差额都称为加载失败，但 ARC4 错误证明至少存在真实 provider/加载缺口。466 vendor-module 审计不能覆盖 stock system_dlkm/GKI 的完整集合、依赖关系和加载顺序。

### 11.3 双卡通话和移动数据

R62：

- 用户确认两张 SIM 均进行了实际拨号，均未完成通话；
- phoneId 1 有完整 RIL 证据：

~~~text
19:55:31.128 > DIAL [PHONE1]
19:55:45.141 < DIAL error 46 [PHONE1]
INVALID_MODEM_STATE
~~~

- 约 15 分钟观察内移动数据不可用，关闭 Wi-Fi 后未形成有效默认移动路由。

stock 对照：两张 SIM 均走 IMS 并进入 `DIALING → ALERTING → ACTIVE → DISCONNECTED`；关闭 Wi-Fi 120 秒，默认路由稳定通过 `rmnet_data2`，数据状态 connected。

因此 SIM、运营商、套餐和 APN 不能解释 R62 与 stock 的差异。

### 11.4 DSI 初始化回调：最早、最直接的分叉

R62 首次失败：

~~~text
19:54:20.730 getDataHandle - unable to generate dsi_handle
19:54:20.730 dsi_get_data_srvc handle returned NULL so wait for dsi_init_cb
~~~

在后续多个时间点仍反复失败，始终没有：

~~~text
dsi_init callback received
dsi_init callback posting to DsiNetctrlClient
getDataHandle: dsi_handle created successfully
~~~

stock 也可能首次拿不到 handle，但约 2.357 秒后恢复：

~~~text
20:12:35.289 dsi_get_data_srvc handle returned NULL
20:12:37.646 dsi_init callback received
20:12:37.646 dsi_handle created successfully
~~~

两边都启动 `vendor.nicmd`、`vendor.dataqti`、`vendor.dataadpl`，都完成 QRTR HELLO、QMI IPA modem init、`rmnet_ipa0`、`rmnet_ctl`、DFC QMAP、WDA、DPM/modem-in-service 等步骤。设备属性为 `ro.vendor.use_data_netmgrd=true`；`libdsi_netctrl.so` 表明后续路径涉及 `dsi_init_query_nicm`、OEM proxy、netmgr readiness、`libnicm.so`/`libnicm_dsi.so`。

现有日志没有捕获其中某个内部步骤的唯一失败行。因此准确边界是：

> R62 下 Qualcomm DSI 数据控制库没有完成 readiness/初始化回调，IMS daemon 无法创建 DSI handle；default/IMS bearer、移动数据、IMS 注册和 IMS 通话被统一阻断。更深层触发原因尚未唯一定位。

### 11.5 bearer 失败不是“IPA/rmnet 完全没起来”

C0、v5 和 stock 的直接对比：

~~~text
C0    19:49:47.390 SETUP_DATA_CALL
      19:49:47.394 OEM_DCFAILCAUSE_4(0x1004), cid=-1, ifname=""

v5    20:00:19.893 SETUP_DATA_CALL
      20:00:19.895 OEM_DCFAILCAUSE_4(0x1004), cid=-1, ifname=""

stock 20:34:27.687 default APN request
      20:34:28.061 cause=NONE, cid=0, rmnet_data2
      20:34:29.991 IMS APN cid=1, rmnet_data1, P-CSCF
~~~

C0 在失败前已经有 QMI IPA modem init、`rmnet_ctl` probe、rmnet/IPA 注册、DFC QMAP、`ipam`、`rmnet_core`、`qmi_helpers`、QRTR 和 MHI 加载证据。因此不能把 `OEM_DCFAILCAUSE_4` 擅自解释为 IPA 错误或某个具体 Qualcomm 内部错误；公开 AOSP 只将其视为 OEM 保留码。

### 11.6 system_server 崩溃是第二条故障链

第一轮 R62：

~~~text
19:54:20.730 DSI handle 首次失败
19:54:27.412 system_server PID 4915 SIGSEGV, SEGV_MAPERR, fault addr 0x0
19:54:30.513 新 system_server 启动
~~~

LSPosed/HMA/HyperCeiler/`com.huaMax` 注入仍在运行，崩溃位于匿名 Dalvik JIT/DEX 路径。它可以解释桌面/锁屏切换、黑屏/亮屏和服务重启，但因为 DSI 失败早约 6.7 秒，所以不可能是蜂窝最初分叉。stock-identity R62 未复现这一崩溃链，但蜂窝仍失败，进一步支持该判断。

### 11.7 最高优先级嫌疑

- R62 kernel 与 stock system_dlkm/GKI 模块集合和加载顺序未完整配对；
- 第一轮没有使用 exact R62 KernelSU LKM；
- ARC4/mac80211 missing symbol 证明运行时 provider 集合不完整；
- 与 stock 相比仍缺少 Xiaomi 专有调度、存储、I/O 和内存扩展；
- framework 注入污染稳定性，但不是最初 DSI 失败根因。

`wwan.ko` 缺失只是配对不完整证据；R62 与 stock 都出现过 `wwan_ptr (private)=NULL` 且都能创建 `rmnet_ipa0`，不能单独定为 DSI 根因。

## 12. stock-identity R62 与无效实验

### 12.1 stock-identity R62 再测试

重新构建并对齐 stock release 的历史产物：

| 产物 | SHA-256 |
|---|---|
| R62 Image | `849e3438af8ccfab93e77d40836157c662e0c4e8a455f8de537c6c05a1901689` |
| vmlinux | `6047e3457f9b006514c33a5a1b1a454659a07d0d96128ac651f44c246a304b6d` |
| exact KernelSU LKM | `48a9aa0bc90789395965c8a36255c8422e1af2b9531d9d9956eacbe7705c1368` |
| boot candidate | `9247587ff7683938de3affd33fcbd1860a04b3b3957ecf1bd52f7e80c500c5c2` |
| init_boot candidate | `b80042327f7693d49062893202f13313aca702e7fd8724d115a60c6d8ab223ba` |

运行时 kallsyms 出现 `init_ipc_ns`、`put_ipc_ns`、`alloc_task_dma_buf_info`、`rfkill_register` 等 R62 特有导出，证明实际运行的是自定义 R62，不是 stock 误判。仍出现：

~~~text
21:23:14.251 getDataHandle - unable to generate dsi_handle, retry on receiving dsi_init_cb
21:23:14.251 dsi_get_data_srvc handle returned NULL so wait for dsi_init_cb
~~~

仍无 `dsi_init_cb`，没有 IMS 或移动数据；该轮没有复现第一轮明显的 framework crash。

### 12.2 第一次最小 RFKILL 通话成功：撤回

第一次最小 RFKILL 测试电话打通，但事后解包发现 boot 中仍是 stock Image，原因是 repack 工作目录错误。该结果不能归因于自定义内核。

### 12.3 修正后的最小 RFKILL候选

| 产物 | SHA-256 / 大小 | 结果 |
|---|---|---|
| corrected Image | `db21b5f40da467953d862c34ab17da32c20ca25b2a4f48c02260ce02f200e825` / 40049152 bytes | 未进入 ADB，黑屏 |
| corrected boot | `8c67116ed2640a107ce4a059a2099fc538fbe0e4cac4d86a48767b61880d943d` | 无业务结论 |
| 手工字符串 identity Image | `9757fb28727cf8b11378b2eb1a8ebb8da5ff15119b6768371eb4865c14912f8c` | 非正式构建方法 |
| 手工字符串 identity boot | `53838d5a21897f40c6a9c816790b7f886126666743f4a886edfb7fbffe49e695` | 未进入 ADB |

未完成启动的镜像不能用于通话/蜂窝归因；直接修改 Image release 字符串也不能作为正式候选。

## 13. 显示、Logo 与锁屏现象

多次 `fastboot boot`，包括 stock 临时启动，也观察到小米静态 Logo 不显示或黑屏，随后出现澎湃 OS 动画或系统界面。因此：

- 更可能与 fastboot early splash/display handoff 有关；
- 不能据此归因到蜂窝或某个显示驱动函数；
- 第一眼看到桌面不等于证明绕过锁屏，可能是旧 scanout、Keyguard 尚未建立或 framework 重启中的短暂画面；
- 第一轮 R62 framework 崩溃可解释回锁屏和黑屏/亮屏链，但 stock-identity R62 未复现该崩溃而蜂窝仍失败。

## 14. 已证实、已推翻与未证实

### 14.1 已证实

- Droidspaces 6.12 改动需要源码级构建，不能只改现有 boot 二进制。
- 本地 Kleaf/Bazel 可以完成 ARM64 GKI 构建。
- 初版 flash 失败来自 boot/AVB 结构丢失，而非内核代码运行失败。
- bootloader 能接受部分重打包镜像进行 `fastboot boot`。
- 通用 KernelSU LKM 会在不匹配内核上 panic；exact LKM 可消除该 panic。
- 早期 R00 与 Xiaomi vendor modules 存在真实 CRC mismatch。
- stock `vendor_data_pad` 是 1024 bytes，对外 CRC 是 `0xf54e5881`。
- Android 正式 KABI type rule 能合法复现该组合。
- 最终 466 vendor modules 静态审计全绿。
- RFKILL 内建修复使 v5 的 Wi-Fi、蓝牙和热点基础链路可用。
- C0/v5 基于 R00，不是 stock 的 RFKILL 单变量修改。
- R62 自定义内核真正运行过，但 DSI callback、移动数据、IMS 与通话失败。
- 用户实机确认 R62 下相机、指纹、Wi-Fi 和蓝牙正常；现有证据不支持“R62 导致大多数硬件失效”。
- stock 基线两张 SIM 通话与移动数据正常。
- 当前设备分区已恢复且与最初备份一致。

### 14.2 已推翻或修正

- “vermagic 主字符串相同就兼容”——被 `module_layout` CRC mismatch 推翻。
- “旧 8+20/28 项仍是 bootfirst 失败根因”——后续审计已归零。
- “`-maybe-dirty` 是模块加载失败核心”——修正为 identity/provenance 问题，CRC 才是已证实阻断。
- “RFKILL v5 尚未测试”——2026-08-23 已长测。
- “RFKILL 内建能修蜂窝”——v5 实机否定。
- “C0/v5 只改了 RFKILL”——实际基于 R00 并伪装 stock identity。
- “最小 RFKILL 内核电话成功”——实际运行 stock，结论撤回。
- “system_server 崩溃导致最初蜂窝失败”——DSI 失败早约 6.7 秒。
- “缺少 wwan 已证明是根因”——仅能证明配对不完整。
- “恢复 stock init_boot 就是移除 Root”——该镜像实际是最初 KernelSU 基线。
- “看到桌面证明绕过锁屏”——没有证据。

### 14.3 尚未证实

- DSI callback 丢失由哪个具体内核函数、模块或 readiness 协议触发；
- 完整 R62-compatible system_dlkm 配对后蜂窝是否恢复；
- 无 KernelSU、无 Zygisk/LSPosed 注入的干净 R62 是否仍复现；
- Xiaomi 专有调度、UFS/F2FS、I/O 或内存扩展中哪一项具有决定性影响；
- Droidspaces requirements 在最终、干净、蜂窝正常的候选上是否全部通过；
- 容器长期稳定性、休眠唤醒、音频、USB、充电和压力测试结果；相机仅有用户功能确认，尚无系统化长测。

## 15. 如果继续研究：正确实验设计

### 15.1 构建

1. 使用同一 R62 manifest、common commit、Kleaf、Clang 和 Bazel。
2. 先构建只保留必要 RFKILL 差异的最小候选，再逐项加入 Droidspaces 的 SYSVIPC/POSIX_MQUEUE/IPC_NS/PID_NS/DEVTMPFS。
3. 不移植旧 18 个占位 hook。
4. release identity 在构建阶段生成；禁止事后修改 Image 字符串。
5. 固化 Image、vmlinux、`.config`、kernel.release、Module.symvers、vmlinux.symvers、build log、source commits 和 SHA256SUMS。

### 15.2 运行时配对

1. 配齐与 R62 kernel 对应的 system_dlkm/GKI modules，先消除 `libarc4/mac80211` 缺口。
2. 使用同一构建输出生成 exact KernelSU LKM/init_boot，或先做无 KernelSU 对照。
3. 经用户明确授权后，临时禁用会注入 `system_server` 的 HMA/LSPosed/Zygisk/HyperCeiler 类模块，避免第二条故障链污染。
4. 不修改 radio、carrier、IMS 或 APN 作为修复尝试，先保持用户态配置一致。

### 15.3 候选离线验收

每个 boot candidate 必须重新解包并记录：

- 实际嵌入 Image SHA-256；
- kernel size；
- UTS release/Linux version；
- boot header；
- AVB descriptor 与 payload 是否匹配；
- init_boot 中 LKM SHA、vermagic、条目元数据；
- vendor 与 system_dlkm 模块依赖闭合情况。

目录名、文件名和 `latest` 不能作为内容证据。

### 15.4 设备测试

1. 再次确认 `current-slot=a` 和 A 槽基线哈希。
2. 不使用 slot B。
3. 自定义 boot 只通过 `fastboot boot`，不写 `boot_a`。
4. 从开机前同步采集 dmesg、all/radio logcat、boot reason、pstore、NICM/DSI 调试信息。
5. 开机后先证明实际 kernel identity、Image 和模块集合，再进行业务测试。
6. 业务验收至少包括：`sys.boot_completed=1`；无 panic/watchdog/reboot loop；Wi-Fi 扫描、连接、热点；`dsi_init_cb` 与 DSI handle；default/IMS APN 有有效 cid、ifname、DNS、P-CSCF；双卡 IMS 注册、双卡实际通话、双卡短信；关闭 Wi-Fi 后移动数据路由。

### 15.5 未经授权的操作

未经再次明确授权，不执行自动拨号或发短信、禁用/删除/修改 HMA/LSPosed/Zygisk、重启设备、修改 radio/carrier/IMS/APN、刷写任何分区、清空 logcat 或 pstore。

## 16. 恢复原则与原始备份校验

当前设备已恢复，不应为了“确认”而再次写分区。未来若测试临时修改 `init_boot_a`：

1. 测试前完整读取 `boot_a` 与 `init_boot_a` 并校验；
2. 恢复目标必须是最初 KernelSU `init_boot_a`，不是无 Root 的纯 stock init_boot；
3. 写入后、重启前完整回读 `init_boot_a`；
4. 只有哈希等于 `bc9bc4d84a03b41f2ce159ff423ccaf12fcef2badc3d94fbb4e84d2e5bdf6310` 才允许重启；
5. 重启后再次回读 `boot_a` 与 `init_boot_a`；
6. 不触碰 slot B、用户数据、DroidSPACE 软件或配置。

以下 16 个文件已于 2026-08-25 从现存备份重新计算并全部通过：

~~~text
af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b  boot_a.img
425382d5857f04fc49585cabbdef6fc647472ee26f52c54caaaeaad17320b3f8  boot_b.img
1fe1bbb950c9b4f004814ccee079292b0cced1945719014e7f700ca30a6a2cfc  dtbo_a.img
83ee47245398adee79bd9c0a8bc57b821e92aba10f5f9ade8a5d1fae4d8c4302  dtbo_b.img
89356d31c661d383ea400471418c642c3a61cc78962556c164ac2988d67d04ea  getprop.txt
bc9bc4d84a03b41f2ce159ff423ccaf12fcef2badc3d94fbb4e84d2e5bdf6310  init_boot_a.img
2daeb1f36095b44b318410b3f4e8b5d989dcc7bb023d1426c492dab0a3053e74  init_boot_b.img
7f8fc48c64b285bfe076d25a073dec1ace8dc3660deada0a2c737c0a1f7e3fbd  kernel.config.gz
d43d3d716436974ced8ad530852326eb21dedc425ceb095a8b05f2f68db44002  ksu_backup_aaabe93ba94a588781de33e6c259e6f90b132430.ko
17c1d8350a4c56c19acb68a2c25882c76aaa6ec7f2943870a8979e51145c2f9c  ksu_backup_d6daa723043cd93cedfbe8b9231ff5e4d26f3d7c.ko
0f2f86d782f7304c28e9e20dc3c3ddfe2e77038c7280ed220002ecb83fa96584  magiskboot
524d2d1f96281839c2e6bc4f1c7a24afc25fd9294812d1d6a73fb702d9c4d8f3  uname.txt
2abe2d9a355ca4db21bb29f980d7ce19310cab7be849b089d9e5f6a9896433db  vbmeta_a.img
af1e5cfcde01524514096d9d801b03fc8d128d48add4e61176e99d9d85020287  vbmeta_b.img
54a2e92fadcd28dd77a90aaf6fdb61e920f6f4913bb7597cedf0714350dee4c7  vendor_boot_a.img
425382d5857f04fc49585cabbdef6fc647472ee26f52c54caaaeaad17320b3f8  vendor_boot_b.img
~~~

## 17. 工程经验摘要

1. 所有成功先证明实际运行对象；一次 repack 目录错误足以把 stock 误判为 custom 成功。
2. 哈希是实验身份；同一路径会被多轮构建覆盖。
3. 构建、静态兼容和业务兼容是不同层；466 modules 全绿仍可能因 system_dlkm、加载顺序和用户态 readiness 失败。
4. GKI 版本文本不是源码等价；R00 stamp 成 stock 名字也不会获得 R62 的真实 hook 和运行时语义。
5. `ANDROID_KABI_TYPE_STRING` 是解决真实对象大小与公开 ABI CRC 双重约束的正规机制，不能关闭或伪造 CRC。
6. KernelSU exact LKM 是独立且已验证的必要工作，但不能解决 vendor/system module 不兼容。
7. AVB 外形不等于有效签名；修改 payload 后原厂 descriptor 必然失效，候选只做临时启动。
8. Wi-Fi 与蜂窝必须分开验收；RFKILL 修复了 Wi-Fi，却没有修复 DSI/IMS。
9. DSI 失败早于 framework 崩溃，不能倒置因果。
10. 未完成启动的镜像没有业务结论。

## 18. 到货旧字库与当前系统的版本边界

到货、尚未升级系统时的完整备份位于：

`backup/字库备份_1784207149608/`

旧、当前 `boot_a` 已直接解包并复算：

| 项目 | 到货旧系统 | 当前系统 |
|---|---|---|
| `boot_a` SHA-256 | `9109c025f530e8eafd9b10a03ad8a15e39f876d12e43c102daf87f21f0782ba5` | `af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b` |
| kernel release | `6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k` | `6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k` |
| Image SHA-256 | `4441e484563158ae961f0938462fa9a6ba54024a800329c4339f39a5ac8e35c8` | `574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2` |
| Image 大小 | 39,963,136 bytes | 41,507,328 bytes |
| 编译时间 | 2025-11-27 08:45:40 UTC | 2026-05-20 14:26:34 UTC |

两个 boot 都是 header v4，Clang 均为 r536225 系列，但它们属于不同的 Android GKI release family。旧字库包含 `super`、vendor boot、DTBO、VBMeta、modem 和大量固件，仍有模块清单、设备树和旧 ABI 研究价值；它不能因为“文件齐全”就被当作当前设备的安全整机降级包。

防回滚约束必须与 BL 解锁状态分开：

- 当前 BL unlocked 不等于 rollback index 被清除。
- 旧分区镜像不等于已经备份硬件或 RPMB 中的最低允许版本。
- 不尝试把旧 ABL、XBL、TZ、modem firmware 或整套旧字库写回当前设备。
- 当前完整字库是主开发基线；旧字库只用于离线比较。

## 19. 小米公开源码与依赖审计

2026-08-26 的历史调研记录指向：

| 内容 | 记录值 |
|---|---|
| 小米内核仓库 | `MiCode/Xiaomi_Kernel_OpenSource` |
| 分支 | `popsicle-w-oss` |
| 当时记录的 HEAD | `45705be1220b4cfa8100516ad86711656c0b634e` |
| 设备树仓库 | `MiCode/kernel_devicetree` / `popsicle-w-oss` |
| 当时记录的 HEAD | `667482462e15458b602a2688a94efd47a5010141` |
| ACK tag | `android16-6.12-2025-06_r8` |
| ACK commit | `f1bdb13583da85a47fcf1632a78ef52d6e6da651` |
| Clang | `r536225` |
| Rust | `1.81.0.u1` |

这些仓库后来已从本地删除，因此以上 commit 是历史审计记录，不表示当前远端 HEAD。真正执行构建前必须重新拉取并固定 commit。

### 19.1 它不是完整的一键构建工程

公开仓库预期自己位于一个已经由内部 manifest 同步好的多仓库工作区：

~~~text
workspace/
├── common/
├── soc-repo/                    # Xiaomi_Kernel_OpenSource
├── build/kernel/
├── prebuilts/clang/host/linux-x86/clang-r536225/
├── external/qcom-dtc/
├── bootable/bootloader/edk2/
├── kernel_devicetree/
└── 其他 Qualcomm/Xiaomi 模块仓库
~~~

构建文件中的 `//common`、`${ROOT_DIR}/soc-repo`、`${ROOT_DIR}/external/qcom-dtc` 等都是本地 Bazel/workspace 路径，不是依赖下载地址。公开内容没有提供完整 `repo manifest`、顶层一键同步脚本以及所有依赖的 URL + commit。

### 19.2 依赖分类

1. **核心强依赖**：精确 `common`、兼容的 `kernel/build`/Kleaf、Clang、`soc-repo` 和关键设备树；缺失时不能生成目标内核。
2. **可跳过目标**：EDK2/ABL、完整 bootloader、虚拟机和非必要 ABI 报告；仅构建 Image、模块和 DTBO 时不必一开始补齐。
3. **可继续使用原厂二进制的组件**：部分 Qualcomm/Xiaomi vendor module 与固件；前提是新内核严格保持其所需 KMI、CRC、加载顺序和运行语义。

当前最敏感的缺口是 Qualcomm `dataipa`、`datarmnet` 等蜂窝数据相关组件的精确源码/版本。它们是否必须重新编译，必须由 Bazel 依赖图和当前 `vendor_dlkm` 实物决定，不能只靠仓库名称推测。

### 19.3 社区路线的能力边界

历史调研找到过小米 17 的通用 GKI/AnyKernel 项目，例如 `YuzakiKokuban/android_kernel_xiaomi_sm8850`、Kokuban CI 和 Picters Kernel。这些项目证明“为小米 17 构建并打包通用 GKI”已有社区实践，但没有公开证据充分证明完整完成：

~~~text
popsicle-w-oss
→ pudding_perf
→ Image + vendor_dlkm + dtbo
→ 小米 17 实机启动
→ SIM / 数据 / IMS 全部正常
~~~

所以必须区分两个目标：

- **完整复现小米官方构建**：需要完整 manifest、精确依赖和内部构建参数，风险高。
- **构建可用的 Droidspaces GKI**：可采用当前 ACK、当前原厂模块和严格配对，未必需要重编全部厂商组件。

### 19.4 小米源码路线的停止条件

先进行短周期依赖审计，不进行无限补洞：

1. 建立最小工作区。
2. 执行 Bazel `query` 和最小 `pudding_perf` build。
3. 记录每个缺失 target，并分类为必需、可跳过或可由原厂二进制替代。
4. 如果发现某个运行必需、无法跳过、无法由当前原厂二进制替代且公开渠道不存在的强依赖，立即停止完整官方复现路线。
5. 不把“完整官方复现失败”等同于“通用 GKI + 原厂模块路线失败”。

## 20. Goldzxcbug / Droidspaces 补丁路线记录

历史审计对象为 `Goldzxcbug/Droidspaces_Kernel_patch`，当时记录 commit：

`d8bf6769d0d5781d17701625a4dd8de42267768d`

必须区分两套内容。

### 20.1 教程工作流实际使用的小补丁

云编译教程实际引用的是：

~~~text
ravindu644/Droidspaces-OSS
Documentation/resources/kernel-patches/GKI/kernel-6.12/
001.GKI-6.12-or-above-fix_sysvipc_kabi.patch
SHA-256: 059db74ecf615273785f25c54b0b26f61cee9ea330d3b4787cdfd8172778eaad
~~~

该补丁约 33 行，主要在 `include/linux/sched.h` 中利用 KABI 预留空间容纳 SYSVIPC 相关状态，与历史 R62 对 SYSVIPC KABI 的基本方向接近。

### 20.2 仓库中的大补丁

`GKI/6.12/Kernel_6.12.patch` 历史记录约 3822 行、涉及 56 个文件，通过结构扩展、KABI reserve、指针高低位拆分/重组和额外间接访问支持更多 namespace/cgroup/netfilter/perf/SCTP 等能力。所谓“地址映射”不是 MMU 页表映射。其预期直接性能损失较小，真正风险在并发生命周期、缓存、结构布局和模块实际 ABI。

大补丁中曾记录以下高风险改动：

~~~diff
bad_version:
- return 0;
+ return 1;
~~~

这会让符号版本不匹配的模块继续尝试加载。未经模块级审计和实机隔离验证，不采用关闭/绕过版本检查的方案。

### 20.3 已复现的云编译产物边界

历史复现输入：

~~~text
kernel_version=6.12
os_patch_level=2026-03
kernelsu_variant=ReSukiSU
droidspaces=678
cancel_susfs=true
droidspaces_ntsync=false
~~~

输出内核：

~~~text
6.12.69-android16-5-g2a80d5991392d-ab10010017-4k
Image SHA-256: f74113508b0d5386a23cf42daf0d81705fad127382628018b08ec56d88a032fc
~~~

它属于 `android16-5`，当前 stock 属于 `android16-6`；该工作流 boot 使用测试 AVB 密钥，而且没有保留完整 `vmlinux`、`Module.symvers`、`vmlinux.symvers` 和配套 modules。它只证明工作流可以产出 Image，不是可直接刷写候选。

## 21. 非官方 BL 解锁链及其工程意义

以下解锁流程由设备所有者提供，应记录为本机历史事实，而不是根据普通 BL 状态推测：

~~~text
Android 内核竞态类提权漏洞
→ 临时获得 Root / 块设备写权限
→ 写回 3 月前的旧 ABL
→ 利用旧 ABL/GBL 签名验证缺陷运行未受信任 EFI 程序
→ EFI 调用高权限设备状态接口修改 BL lock 状态
→ 设备保持持久化 unlocked
~~~

第一阶段内核漏洞的准确 CVE 尚未由本地文件确认，不在本文猜测。当前项目只利用最终已经存在的 unlocked 状态，不重新执行漏洞。

### 21.1 对内核项目有帮助的部分

- 解释没有小米 AVB 私钥的自定义 boot 为什么仍可能被 bootloader 接受。
- 提供临时启动、测试失败后恢复原厂 boot 的操作条件。
- 如果普通 fastboot 路径失效，历史 EFI/GBL 工具具有救援和启动前诊断价值。
- 使“构建 → `fastboot boot` → 采集日志 → 回到 stock”的单变量循环成为可行工程路线。

EFI/GBL 只作为备用救援通道，不作为常规内核验证路径。通过 EFI 链式加载可能改变正常 ABL/AVB/DTBO/vendor_boot 启动环境，产生不可比较的结果。

### 21.2 它不能解决的部分

- 不提供小米未公开的源码或 manifest。
- 不让错误 KMI、CRC 或 vermagic 的模块自动兼容。
- 不补齐 `system_dlkm`、`dataipa`、`datarmnet` 或 DSI 回调。
- 不等于获得 Qualcomm/小米签名私钥，也不表示 Secure Boot 根信任被替换。
- 不等于关闭 AVB rollback index、固件 anti-rollback、RPMB 或 eFuse/QFPROM 检查。
- 不直接修复 SIM、数据、IMS 或通话。

### 21.3 旧、当前启动链镜像对比

对到货旧字库和 2026-08-26 当前完整字库进行只读 SHA-256 比较：

| 分区 | 到货旧字库 | 当前完整字库 | 判断 |
|---|---|---|---|
| `abl_a` | `f7add50353d5eb9159dd89945cf9003f0f7f904b6a5525da9e0bc324a52cee88` | `36c2426de6667643dda74779d26d6472864dcf7f4da4aabd9a23025ed1b2cc31` | 不同 |
| `abl_b` | `f7add50353d5eb9159dd89945cf9003f0f7f904b6a5525da9e0bc324a52cee88` | `2cd2274cfd7db57dbc4784c4c980c1ec15b52cc65fcb446dd557e6127c4e5277` | 不同 |
| `devinfo` | `605aedf37d67c17ce9f067475db60f4e8045a74e68e01c2203184b676f9de14f` | 同左 | 相同 |
| `efisp` | `bbd05cf6097ac9b1f89ea29d2542c1b7b67ee46848393895f5a9e43fa1f621e5` | 同左 | 相同 |
| `uefivarstore` | `fa9d8775f63eeb67eff9ac477cfb3be671d68f620a2d3726e093a6567048a4b5` | 同左 | 相同 |

此外，`xbl_a/b`、`xbl_config_a/b`、`uefi_a/b`、`uefisecapp_a/b` 和 `vbmeta*` 均不同；当前 `abl_a != abl_b`，当前 `xbl_a != xbl_b`。这只能证明当前启动链二进制与到货备份不同，不能仅凭哈希判断具体修复内容。

`devinfo`、`efisp`、`uefivarstore` 相同也不能证明 BL 状态存放位置：旧备份可能已经处于解锁后状态，而且持久化锁状态可能位于普通字库无法读取的防篡改存储。当前 ABL 与旧 ABL 不同，因此不能假设当前固件仍可重复利用原漏洞。

需要长期保存但不重新执行：旧 ABL、当时的 EFI payload、临时 Root 工具、操作日志、版本和 SHA-256。未经明确授权，不写 ABL/XBL/UEFI/efisp，不为检查状态主动重启设备。

## 22. 后续工程路线与停止条件

后续不再闭眼长时间试错，按以下阶段推进。每阶段必须有输入、输出和停止条件。

### 阶段 A：冻结当前 stock 证据

**输入**：2026-08-26 当前完整字库。

**输出**：完整分区清单、大小、SHA-256、活动槽、boot Image 身份、动态分区列表。

**停止条件**：关键镜像损坏、哈希不稳定或备份不完整时，不进入构建和实机测试。

### 阶段 B：解析当前模块基线

**输入**：`super.img`、`vendor_boot` 和运行时资料。

**输出**：`system_dlkm/vendor_dlkm/odm_dlkm` 全部模块、`modules.dep`、`modules.alias`、`modules.load`、vermagic、CRC、加载顺序和 stock `/proc/modules` 对照。

**目标**：解释历史 R62 约 584 个运行模块与 stock 约 670 个运行模块之间的差额，并优先检查 IPA、RMNET、QRTR、MHI、WWAN、`libarc4/mac80211` 链。

**停止条件**：如果无法构造与测试 Image 精确匹配的 `system_dlkm`，不进入 Droidspaces 配置归因。

### 阶段 C：纯 android16-6 控制内核

**输入**：当前 stock 对应的 `android16-6` common/Kleaf/Clang 和当前模块基线。

**变量控制**：无 KernelSU、无 Droidspaces 新配置、无 Zygisk/LSPosed/HMA/HyperCeiler 注入；只做建立可复现构建所需的最小改动。

**输出**：Image、vmlinux、`.config`、kernel.release、Module.symvers、vmlinux.symvers、完整 dist/modules、构建日志和 SHA256SUMS。

**验收**：只用 `fastboot boot` 临时启动；先确认实际运行 Image 和模块集合，再测试 SIM/数据/IMS。

**停止条件**：如果纯控制内核仍无 `dsi_init_cb`，问题属于 GKI/模块/厂商蜂窝栈配对，不继续加入 Droidspaces 配置。

#### 2026-08-26 R30 控制版当前进展

已锁定并完成 `android16-6.12-2026-03_r30` 的纯控制构建：

~~~text
kernel release: 6.12.69-android16-6-4k
Image size:     42097152 bytes
Image SHA-256:  9888b71a440c6713f820fe4e1775f460bb9ae6272444bdeaba5039357ae59a24
~~~

Kleaf 导出的 64 MiB 通用 `boot.img` 不再作为设备候选。设备候选以当前原厂
96 MiB `boot_a.img` 为模板，经 MagiskBoot 只替换 kernel，并在重打包后重新
解包验证：

~~~text
stock template SHA-256: af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b
candidate size:          100663296 bytes
candidate SHA-256:       b66b1d547142fcedea03b9d1b270a41b19eb7dd53b36dad1fba5d5413b7eb6e6
embedded kernel SHA-256: 9888b71a440c6713f820fe4e1775f460bb9ae6272444bdeaba5039357ae59a24
header version:          4
ramdisk size:            0
~~~

两次独立重打包得到相同 candidate SHA-256。候选保留 `AVB0`/`AVBf` 外形并
复用原厂 vbmeta 数据，但修改 kernel 后原厂 AVB 签名在密码学上不再有效；
它只允许用于解锁 bootloader 下的 `fastboot boot` 临时测试，严禁刷写。

此前直接尝试 64 MiB 通用 GKI `boot.img` 的过程被用户手动进入 fastboot
打断，不能用于判断 R30 是否能启动。该错误路径已停止。随后对 96 MiB 原厂
模板候选进行了正式 `fastboot boot` 测试：设备持续黑屏且没有出现 ADB，用户
约两分多钟后手动进入 fastboot；进入前瞬间观察到绿色小米 Logo。绿色现象
只作为显示 handoff/旧 framebuffer 观察记录，不能据此认定显示驱动是根因。

恢复后的 ramoops/pstore 明确记录：

~~~text
Linux version 6.12.69-android16-6-4k (kleaf@build-host)
~~~

因此 R30 Image 已真正获得执行权，boot 模板也不是本轮黑屏的直接解释。日志
最后可辨识时间约为 10.72 秒，没有捕获明确 `Kernel panic`、Oops 或自动重启行；
用户手动进入 fastboot 终止了后续观察。当前直接证据包括：

- 原 `init_boot_a` 中 KernelSU LKM 报
  `no symbol version for module_layout`，但日志继续推进，尚不能把它唯一确定为
  本轮停止点；
- `mi_memory_monitor.ko` 缺少
  `__tracepoint_android_vh_mm_direct_reclaim_end` 并加载失败；
- stock 运行时有 798 个 Android tracepoint，R30 输出有 790 个，stock 独有 8 个：
  `cma_alloc_lat_start/end`、`dma_heap_buffer_alloc_lat_start/end`、
  `f2fs_is_hiprio_task`、`f2fs_is_usr_task`、
  `mm_direct_reclaim_start/end`；
- 多个 SMMU TBU probe 失败，`arm-smmu` 出现 deferred-probe timeout/`-110`，
  随后 QUP、GPI DMA、CCI 等设备等待 `15000000.apps-smmu` supplier。

这与本文早期 vendor 模块不兼容导致显示、电源、存储和 SoC deferred probe、
设备黑屏的模式一致，也与 R62 后来补齐 dma-heap、CMA、direct reclaim 等真实
vendor hook 的记录一致。准确边界是：**R30 原样与当前小米 vendor/runtime 模块
栈不兼容，无法进入 ADB；现有 pstore 尚不足以把唯一致命触发点定为 KernelSU、
某一个缺失 hook 或 SMMU。**

本轮也暴露流程偏差：阶段 B 的当前模块基线尚未完成，阶段 C 又沿用了带旧
KernelSU LKM 的 `init_boot_a`，不符合“先模块闭合、无 KernelSU 控制”的设计。
因此不继续直接测试 R30，也不在其上加入 Droidspaces 变量。恢复后设备运行 stock
内核，`boot_a`、`init_boot_a`、`vendor_boot_a`、`dtbo_a`、`vbmeta_a` 哈希均与
测试前一致。

#### 2026-08-26 R30 + R31 Xiaomi 兼容链审查结果

随后使用当前字库缓存中的 466 个 `vendor_ramdisk` 模块做了逐导入符号审查。
原样 R30 共检查 22474 个导入，其中 22466 个通过，8 个引用缺失，归并为 6 个
唯一 Android vendor hook：

~~~text
android_vh_cma_alloc_lat_start
android_vh_cma_alloc_lat_end
android_vh_dma_heap_buffer_alloc_lat_start
android_vh_dma_heap_buffer_alloc_lat_end
android_vh_mm_direct_reclaim_start
android_vh_mm_direct_reclaim_end
~~~

这 6 个 tracepoint 的模块期望 CRC 都是 `0x7c5aa8a7`。它们的真实定义、调用点、
导出和 Xiaomi KMI 列表并不在 R30，而是在 R31 首次形成完整链条。R30 标签日期为
2026-05-18，R31 标签日期为 2026-05-21；相关 Xiaomi 提交的作者日期则早至
2026-04-29 至 2026-05-13，因此不能根据公开标签日期断言设备 stock 一定直接基于
R31。小米可能在公开 R31 标签之前已在内部使用这些提交。能够确定的是：**裸 R30
相对于当前 stock vendor module ABI 确实过老。**

从官方 `android16-6.12-2026-03_r30..r31` 历史按原顺序回移了 4 个提交：

~~~text
aa795bd04bdf  ANDROID: GKI: add vendor hooks for Track CMA and DMA allocation latency.
8aa6935b068b  ANDROID: GKI: add vendor hooks for Track direct_reclaim allocation latency.
4faf781e81fc  ANDROID: mm: Export try_to_free_pages supports proactive memory reclamation.
bc587ccd5d16  ANDROID: GKI: update symbol list file for xiaomi
~~~

这四项必须作为整体保留。仅应用两个 hook 源码提交时，新符号不会进入 KMI trim
输出；加入 Xiaomi symbol list 但遗漏 `try_to_free_pages` 的正式导出时，Kleaf strict
KMI 又会以 `Symbols missing from the ksymtab: try_to_free_pages` 拒绝构建。补齐全部
四项后，严格 KMI 构建和 466 模块审查均通过：

~~~text
kernel release:            6.12.69-android16-6-4k
Image size:                42097152 bytes
Image SHA-256:             b501d87e6b62234494d7df2d87cc533ccc8d729325438f082f32d985d0949c72
vmlinux SHA-256:           31fd2f87a33c31317d23a3feb219643a9d33b15719f6d7b0447ba243d5c951d9
Module.symvers SHA-256:    af77d02d0a3e1a7581e8cc416f3b05340364e6d3f3abc01cc2dfa119d09923ab
modules:                   466
imports:                   22474
ok:                        22474
missing:                   0
CRC mismatch:              0
provider conflict:         0
present but unexported:    0
release mismatch modules:  0
flag mismatch modules:     0
audit_pass:                true
~~~

审查通过后生成了 96 MiB 原厂模板候选：

~~~text
kernel-work/artifacts/r30-stock-compat-stock-template/20260826T234152Z/boot-r30-stock-compat-stock-template.img
size:                       100663296 bytes
SHA-256:                    d06380f9ea23cf834cf5f951bbbf7cae8e171ece44117b000c6e0df0ba0829dc
header version:             4
ramdisk size:               0
embedded kernel SHA-256:    b501d87e6b62234494d7df2d87cc533ccc8d729325438f082f32d985d0949c72
structural checks:          pass
vendor module audit:        pass
device boot test:           not run
~~~

手机当时不在 ADB，因此本轮未借设备执行 ARM64 MagiskBoot。为避免产生不同格式，
本地 header-v4 重打包器先使用旧 R30 Image 重建既有 MagiskBoot 候选，结果与
`b66b1d...6e6` 逐字节相同，再用于本轮 Image；该等价性报告随候选一并保存。
候选复用原厂 vbmeta 数据，但修改 payload 后小米 AVB 密码学签名无效，仍然只能
`fastboot boot`，严禁刷写。KernelSU LKM 配对和实机启动尚未验收。

工程结论：原始 R30 不再作为候选；当前 `r30-stock-compat` 是“R30 核心 + R31
全部 Xiaomi 兼容提交”的最小变化诊断候选。纯 R31 仅再多两个与本问题无直接关系
的提交，可作为更完整、版本关系更清晰的后续基线；但在实机测试前，不能把静态
全绿等同于已解决黑屏。

#### 2026-08-27 R30 兼容候选射频全失效的两层根因与最终修复

四项官方补丁候选通过 96 MiB stock 模板由 fastboot boot 成功进入 Android：
sys.boot_completed=1、ADB、显示和主要 vendor 模块均正常。但 Wi-Fi、蓝牙、热点、
移动数据、电话和射频全部不可用。运行模块数为 579，stock 为 670，差 91 个。
缺失集合正好包括：

~~~text
bluetooth hci_uart btqca btpower bt_fm_swr
cfg80211 mac80211 qca_cld3_peach_v2 rfkill
wwan ppp_generic ppp_deflate ppp_mppe l2tp_ppp libarc4
~~~

第一层根因不是 CRC/KMI，而是 Android 查找 system_dlkm 的 release 目录失败：

~~~text
candidate uname -r:
6.12.69-android16-6-4k

stock system_dlkm directory and module vermagic:
6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
~~~

设备上不存在候选短 release 对应的 system_dlkm/lib/modules 目录，因此完整
modules.load 树在加载前即被跳过。三棵 stock 模块树的扩展审查结果仍为零符号
缺失、零 CRC mismatch、零 provider conflict、零 vermagic flag mismatch。开启
CONFIG_MODVERSIONS 时，内核 same_magic() 比较会忽略 vermagic 的第一个 release
字段，但 Android 用户态选择模块目录不会忽略它；这解释了“模块 ABI 可兼容但系统
根本没有尝试加载”的表面矛盾。

第一次加入 common/workspace_status.json 仍生成短 release。进一步检查发现构建机
没有 repo 命令，构建脚本也没有传 --repo_manifest，Kleaf 的实际状态是：

~~~text
STABLE_SCMVERSIONS {}
~~~

构建脚本随后显式使用锁定的
kernel-work/source-locks/r30/checked-out-manifest.xml，并在正式
构建前验证 common SCMVERSION 非空。release 配对候选变为：

~~~text
kernel release:         6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
Image SHA-256:          e2450f4f7ead1b1c9143f6d0af44aec293d0c7e039ec0ca276fb8550b7432ced
vmlinux SHA-256:        40b23c7e82185190109e3d49a8d5be8911cfda562c83c96d5bae6fcfc3d4865f
boot SHA-256:           21ca6f1b7ecb6dd3b7831df98f29c807709775f8bee4df2a8fd2392952253a67
~~~

该候选实机上已经能看到正确目录和 modules.load，但运行模块数仍为 579，射频故障
完全不变。手工加载 libarc4.ko 得到最终决定性证据：

~~~text
modprobe: Failed to insmod .../libarc4.ko: Permission denied
libarc4: exports protected symbol arc4_crypt
~~~

因此 release 目录只是第一层。第二层、也是最终阻断，是模块签名信任：候选配置启用
CONFIG_MODULE_SIG_PROTECT；stock system_dlkm 模块由 stock 构建证书签名，而本地
候选的自动生成证书不同。模块并非因普通 KMI/CRC 检查失败，而是因为签名无法在候选
内核的 trusted keyring 中验证，被视为不可信模块，不能导出 protected symbol。

从原始 boot_a 内的 stock Image 提取到的公开 X.509 证书为：

~~~text
subject:     CN=Build time autogenerated kernel key
serial:      4B2A816CD76DB5930B2A44680C9BAC6639C63607
SHA-1 fp:    87:07:47:78:28:F3:32:AB:95:DA:D6:0B:29:2C:89:7E:C1:4D:2E:C1
DER SHA-256: 64b16ac8cd1b016e297cf70c18d912dacc83f74f6c38b3c495f9b0b15a3c0aa2
valid from:  2026-05-22 06:49:46 UTC
valid until: 2126-04-28 06:49:46 UTC
~~~

该 serial 与 stock libarc4.ko 等 system_dlkm 模块的 sig_key 完全一致。第 6 个本地
补丁只把此公开证书加入 CONFIG_SYSTEM_TRUSTED_KEYS；不包含、也不需要 Xiaomi 或
构建服务器的私钥。最终 vmlinux 内建 keyring 静态提取出两个证书：本次构建自己的
自动签名证书，以及上述 stock module 证书。实机 /proc/keys 也显示：

~~~text
.builtin_trusted_keys: 2
~~~

最终证书信任候选：

~~~text
kernel release:         6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
Image SHA-256:          7c4c3f13a04ae5a63901f91b270070c0c8cd6d40a037ff042baa9d3386f71cdd
vmlinux SHA-256:        e38f86eb5c1f5bda4382d255bd06f2d2ad8eb83d0578ebea6b4b9524b34c1a63
Module.symvers SHA-256: af77d02d0a3e1a7581e8cc416f3b05340364e6d3f3abc01cc2dfa119d09923ab
boot size:              100663296 bytes
boot SHA-256:           aafd350bbd00a2c7a2267d04e3d1745b08aa6cf28938514cc80f7ea5fbdac71d
~~~

最终 boot：

~~~text
kernel-work/artifacts/r30-stock-compat-stock-template/20260827T124841Z-stock-cert-v2/boot-r30-stock-compat-stock-template.img
~~~

使用 fastboot boot 临时启动后的自动验收：

~~~text
sys.boot_completed:                 1
loaded modules:                     670（stock 也是 670）
required radio modules missing:     0 / 15
module signature rejections:        0
Wi-Fi:                              enabled, wlan0 up, connected
Bluetooth:                          enabled, wearable connected
voice registration:                 both subscriptions IN_SERVICE
IMS networks:                       2 x CONNECTED + VALIDATED
cellular Internet network:          CONNECTED + VALIDATED
~~~

恢复加载的关键模块包括 bluetooth、hci_uart、btqca、btpower、bt_fm_swr、cfg80211、
mac80211、qca_cld3_peach_v2、rfkill、wwan、ppp_generic、ppp_deflate、ppp_mppe、
l2tp_ppp 和 libarc4。用户随后从界面侧确认当前“好像所有东西都能用”。自动流程没有
主动拨号、发短信或切换热点，因此 outgoing call、SMS 和 hotspot 仍记录为 not_run，
不能伪写成自动验收项。

实机日志：

~~~text
kernel-work/logs/r30-stock-compat/device-tests/20260827T130221Z-stock-cert-device-test/
~~~

工程结论：当前可用基线是“R30 + 四项官方 R31 Xiaomi 兼容提交 + stock release
identity + stock system_dlkm 公开签名证书”。后续容器配置必须从该基线复制为新
variant，不得直接污染已经通过实机验收的 r30-stock-compat。该镜像仍无有效 Xiaomi
AVB 签名，只允许 fastboot boot，严禁 flash。

### 阶段 D：Droidspaces 单变量递增

阶段 C 已在 2026-08-27 达到 SIM、数据、IMS、Wi-Fi 与蓝牙的可用基线。随后从
该提交复制出独立的 `r30-stock-containers` variant；已验收的
`r30-stock-compat` 和所有 `kernel-work/upstream/` 源码均未修改。

原计划先启用 `PID_NS + IPC_NS`，但 R30 Kconfig 明确规定：

~~~text
CONFIG_IPC_NS depends on (SYSVIPC || POSIX_MQUEUE)
~~~

因此实际按可构建边界拆分为：

1. 删除 GKI defconfig 中的 `# CONFIG_PID_NS is not set`；
2. 启用 `SYSVIPC + POSIX_MQUEUE`，由 Kconfig 自动得到 `IPC_NS=y`；
3. 使用 Droidspaces-OSS 锁定补丁的 KABI 方法，把 SYSVIPC task state 放入
   `task_struct` 原有对齐空洞；
4. 导出 in-tree `rust_binder.ko` 实际引用的 `init_ipc_ns` 与
   `put_ipc_ns`；
5. 用官方 `//common:kernel_aarch64_abi_update` 生成 ABI snapshot；
6. 最后以单独补丁启用 `CONFIG_DEVTMPFS=y`。

没有把 IPC 符号加入公开稳定 GKI symbol list，没有伪造 CRC，没有关闭
MODVERSIONS/strict KMI。最终配置边界为：

~~~text
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_DEVTMPFS=y
# CONFIG_DEVTMPFS_MOUNT is not set
# CONFIG_USER_NS is not set
# CONFIG_CGROUP_DEVICE is not set
CONFIG_RFKILL=m
~~~

DWARF 验证表明 SYSVIPC 字段使用的确是既有空洞，没有移动后续调度字段：

~~~text
sizeof(task_struct): 5184
rt_priority:         160
sysvsem:             164
sysvshm:             172
sched_entity (se):   192
~~~

阶段 2 和最终 DEVTMPFS 构建之间的 `Module.symvers` 完全相同：10,353 个符号，
零新增、零删除、零 CRC 变化。最终 strict KMI 构建与 stock 模块审查结果：

~~~text
kernel release:            6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
Image size:                42166784 bytes
Image SHA-256:             460c4ee4d025bb9fa042068c5ebc8418d1882079529f4951509b8d90bce97232
vmlinux SHA-256:           b99c3771db0d85a4fbcea59af004da6ff7363e7d0022930eebe998e974d14d32
Module.symvers SHA-256:    b48480ea59efc6452667bcd7ccfac9d5a1ad22b43e336cb9ea0227ecca0e7c06
modules:                   466
imports:                   22474
missing/CRC/provider:      0/0/0
strict KMI:                pass
~~~

最终构建与 96 MiB 原厂模板候选：

~~~text
kernel-work/artifacts/r30-stock-containers/20260827T152000Z-final-containers/
kernel-work/artifacts/r30-stock-containers-stock-template/20260827T153000Z-final-containers-stock-template/boot-r30-stock-containers-stock-template.img
boot size:    100663296 bytes
boot SHA-256: a1f844771b61ee75468d943f95c2753d1224ad5c968618145bbae2a9c9b7f715
~~~

本地重打包器仍先重建历史 MagiskBoot 参考候选并达到逐字节一致；最终镜像的
header v4、空 ramdisk、内嵌 Image 和 96 MiB 总长度均通过结构检查。修改 payload
后 Xiaomi AVB 签名无效，所以仍只允许 `fastboot boot`，禁止 flash。

#### 2026-08-27 首版容器实机测试与 stock Rust KMI 漏审

随后对上述首版候选只执行了 `fastboot boot`，没有 flash，也没有使用 slot B。
约 15 秒恢复 ADB，`sys.boot_completed=1`；运行内核的构建时间确认是候选版本。
KSU root、蓝牙、双卡语音/数据注册、cellular VALIDATED 和 IMS 网络记录均正常，
15 个关键无线/蜂窝模块全部存在。Wi-Fi 模块和 `wlan0` 存在，但系统设置在启动后
变为 `wifi_on=0`，日志记录了 SystemUI toggle；自动测试没有擅自重新打开 Wi-Fi，
因此这一轮不能把 Wi-Fi 数据连接写成自动通过。

容器能力 smoke test 全部通过：

~~~text
IPC namespace:              新 inode，与父 namespace 不同
PID namespace:              子 shell PID=1
PID + IPC namespace:        组合成功
/proc/sysvipc/msg|sem|shm:   存在
mqueue private mount:       成功
devtmpfs/mqueue filesystems: 存在
~~~

但启动前 stock 有 670 个模块，首版候选只有 669 个，唯一缺少：

~~~text
rust_binder
~~~

手工 `insmod` 返回 `Invalid argument`。dmesg 显示 19 个 Rust export CRC
mismatch，并缺少 2 个旧 Rust mangled symbol。根因不是真实 C KABI 空洞布局，而是
首版启用 SYSVIPC 后 bindgen 也看到了新增字段和 SysV 类型，进而改变 Rust
`task_struct` binding、匿名 union 编号和 Rust symbol CRC。此前审查的 466 个
vendor_ramdisk 模块只把 stock `system_dlkm` 当 provider，没有把其中的模块当
consumer，因此没有检查到 stock `rust_binder.ko`。

修复拆成两个独立补丁：

~~~text
0012-preserve-stock-rust-kmi-for-sysvipc.patch
0013-update-abi-after-rust-kmi-preservation.patch
~~~

`0012` 只对 `__BINDGEN__` 隐藏新增 SYSVIPC task state 和相关 SysV helper
布局；正常 C 编译仍保留真实字段。`0013` 再用官方
`//common:kernel_aarch64_abi_update` 更新 ABI snapshot，没有手写 ABI 或 CRC。
从 pristine R30 重放全部 13 个补丁后，strict ABI/KMI 构建通过。相对已兼容 stock
的 stage-1 基线：

~~~text
old symbols: 10351
new symbols: 10353
added:       init_ipc_ns, put_ipc_ns
removed:     0
CRC changed: 0
~~~

审查范围随后扩展为 466 个 vendor consumer 加 103 个 stock system_dlkm consumer：

~~~text
vendor modules/imports:      466 / 22474
system_dlkm modules/imports: 103 / 5816
total modules/imports:       569 / 28290
stock rust_binder imports:   234
missing:                     0
CRC mismatch:                0
provider conflict:           0
present unexported:          0
vermagic flag mismatch:      0
~~~

修复后正式构建：

~~~text
Image:
kernel-work/artifacts/r30-stock-containers/20260827T230746Z-rust-kmi-fixed/Image
Image SHA-256:
8dd40a7250932fd94f7023be68c624522da9983783c4236be4ff4d9824a1d284

boot:
kernel-work/artifacts/r30-stock-containers-stock-template/20260827T232346Z-rust-kmi-fixed-stock-template/boot-r30-stock-containers-stock-template.img
boot size:    100663296
boot SHA-256: 6348a94928c9298135fa07c2f44c89b36731af21a3bfcfabc53f99d5aedfdbaf
~~~

该修复后 boot 随后只通过 `fastboot boot` 临时启动，没有 flash，也没有使用
slot B。15 秒恢复 ADB，Android 完成启动；运行内核构建时间为
`Thu Aug 27 23:06:13 UTC 2026`。首版候选启动前的 669 个模块恢复为 670，
stock `rust_binder` 正常加载，最终 dmesg 中 Rust KMI 错误、模块签名拒绝和
panic/oops 均为 0。

自动复验结果：

~~~text
Wi-Fi:                     enabled, connected, VALIDATED
Bluetooth:                 ON, device connected
required radio modules:    missing 0
voice/data IN_SERVICE:     present
cellular VALIDATED:        present
IMS VALIDATED:             2 networks
IPC namespace:             pass
PID + IPC namespace:       child PID 1, pass
SYSVIPC msg/sem/shm:        present
mqueue private mount:      pass
KSU root:                  pass
~~~

日志目录：

~~~text
kernel-work/logs/r30-stock-containers/device-tests/20260827T233007Z-rust-kmi-fixed-device-test/
~~~

至此，修复后的最小容器内核已经通过 strict 构建、569 模块/28290 导入静态审查、
完整 stock 模块加载、无线/蜂窝和 namespace smoke test。仍未自动执行拨号、短信、
热点切换，也未完成完整 Droidspaces 用户态生命周期、休眠唤醒或长时间压力测试。
候选继续只允许临时运行；正常重启会回到持久化 `boot_a`。

#### 2026-08-28 上午近五小时日常使用稳定性复核

用户从临时启动后持续日常使用到 12:25。只通过 ADB 读取日志和状态，没有重启、
刷写、拨号、短信、热点切换或 radio/APN/IMS 修改。最终 uptime 为 17707.54 秒
（4 小时 55 分 7 秒），boot ID 未变化，说明期间没有重启。运行内核仍是正式候选，
670 个模块仍全部加载，`rust_binder` 仍为 Live。

复核结果没有发现阻断性内核或射频故障：保留下来的 dmesg 窗口中 panic/oops/BUG、
lockup/stall/hung task、KASAN/KFENCE、模块 KMI/签名错误、存储致命错误和无线/基带
子系统崩溃均为 0；`oom_kill=0`。Android 在启动稳定后没有新的 Java fatal、
native fatal、ANR、crash 类 `ApplicationExitInfo`，也没有产生当天的新 tombstone
或 ANR trace。最终状态中 Wi-Fi 已连接并 VALIDATED，蓝牙为 ON 且设备已连接，双卡
语音/数据仍为 IN_SERVICE，cellular 与 IMS 均有 VALIDATED 记录。thermal status 为 0，
最终电池约 34°C、CPU 传感器约 47–54°C。

本次也补记了一条此前短测总结漏掉的启动期异常：07:31:03 首个
`system_server` 在 `ComputerEngine.shouldFilterApplication` 中发生
`StackOverflowError`，随后自动重启；最终 `system_server.start_count=2`，
第二个进程此后连续运行，没有再次 fatal。完全相同的调用栈在
`r30-stock-compat` 的 2026-08-27 19:34:36 测试中也出现过，因此它不是容器配置
补丁新引入的问题；但仅凭这一点还不能断言其最终根因与 R30 基线或系统用户态无关。

另有两个非阻断观察项：11:08–11:09 有 15 个后台进程被 Android 以
`LOW_MEMORY` 回收，但内核没有 OOM kill，复核时 `MemAvailable` 约 5.3 GiB；
12:10、12:12、12:18 的三组 keystore/远程密钥供应操作触发 watchdog，约
6.43–6.56 秒后均完成，没有造成进程崩溃。

由于 vendor 日志量很大，内核 ring buffer 已覆盖中间时段；当前可直接复核的是启动
早期约 61–269 秒和末段约 16699–17707 秒。因此可以确认没有重启/panic，并确认保留
窗口无上述严重错误，但不能声称被覆盖的中间区间绝对没有一次性非致命 warning。
`/sys/fs/pstore` 中的内容属于当前启动之前的 reboot-to-bootloader 记录，不是本轮
运行的新 panic。

日志与审查摘要：

~~~text
kernel-work/logs/r30-stock-containers/device-tests/20260828T041954Z-morning-stability-review/
~~~

结论是该候选通过了近五小时普通日常使用稳定性复核，可以进入完整 Droidspaces
用户态生命周期测试；这不等同于已经完成过夜、休眠唤醒或压力测试。

### 阶段 E：小米完整源码可行性短审计

该阶段与可用 GKI 主路线并行但不混淆。只建立最小 `popsicle-w-oss` 工作区并运行 Bazel query/build；遇到第 19.4 节定义的不可替代强依赖立即停止，不无限寻找内部仓库。

### 通用安全约束

- 不承诺“绝对无 bug”；只能定义覆盖明确的验收矩阵。
- 不以“编译通过”或“466 module 静态全绿”代替实机业务验收。
- 未经用户明确授权，不刷写、不重启、不拨号、不发短信、不修改 radio/IMS/APN。
- 不执行完整字库中的 `flashAll.bat`。
- 优先 `fastboot boot`，不使用 slot B 作为回退槽。
- EFI/ABL 漏洞链只归档，不作为常规测试工具重新运行。

本项目当前可信且仍实际存在的核心资料包括：本文、2026-08-26 当前完整字库、外置盘中的到货旧字库，以及本文记录的历史构建哈希与实机结论。被删除的旧源码、构建目录和候选镜像不得假定仍可恢复。
