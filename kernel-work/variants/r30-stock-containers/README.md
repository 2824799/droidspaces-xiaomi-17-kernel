# R30 Droidspaces container variant

本目录是面向 Xiaomi 17 `pudding` 的 Android Common Kernel R30
Droidspaces container 变体。不修改 `kernel-work/upstream/`；补丁只在可丢弃的
worktree 中应用。

## 配置边界

已启用：

```text
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_DEVTMPFS=y
CONFIG_USER_NS=y
```

刻意保持关闭：

```text
CONFIG_DEVTMPFS_MOUNT=n
CONFIG_CGROUP_DEVICE=n
```

SYSVIPC 的 `sysvsem`/`sysvshm` 使用 `task_struct` 原有 28 字节对齐空洞，
真实 C 布局保持：

```text
sizeof(task_struct)=5184
rt_priority=160
sysvsem=164
sysvshm=172
sched_entity(se)=192
```

`init_ipc_ns` 和 `put_ipc_ns` 使用真实导出，没有加入公开稳定 GKI symbol
list；没有伪造 CRC，也没有关闭 MODVERSIONS 或 strict KMI。

## 本次变更：启用 User Namespace

新增补丁 0014-enable-user-namespaces.patch，将 CONFIG_USER_NS 设为 y，用于
Docker、Flatpak、Bubblewrap、浏览器沙箱以及需要用户命名空间的桌面程序。此前已验收
的 20260827T230746Z-rust-kmi-fixed 仍保留在 artifacts 中作为回滚基线；启用该选项
后必须重新完成 strict ABI/KMI、stock 模块审查和设备验证。本次按要求不执行 fastboot boot。

本次 User Namespace 候选已经完成编译、strict ABI/KMI 和 569 个 stock 模块导入审查。
在一台 Xiaomi 17 `pudding` 测试设备上验证了启动、`CONFIG_USER_NS=y` 和
`unshare -Ur` 运行时测试。设备测试记录只保留在本地，不包含设备序列号或备份路径。

## 首版实机测试与 Rust KMI 漏审

首版候选通过 `fastboot boot` 临时启动，约 15 秒恢复 ADB，Android 完成启动。
无线/蜂窝关键模块、蓝牙、双卡注册、cellular/IMS 网络和容器能力 smoke test 均
通过；PID、IPC namespace、SYSVIPC、mqueue 和 devtmpfs 均可实际使用。

但首版只加载了 669/670 个 stock 模块，唯一缺少 `rust_binder.ko`。手工加载时
出现 19 个 Rust export CRC mismatch 和 2 个旧 Rust mangled symbol 缺失。根因是
`CONFIG_SYSVIPC` 新布局被 bindgen 看见，改变了 Rust `task_struct` binding 和匿名
union 编号；此前 466 模块审查只把 `system_dlkm` 当 provider，没有把其中的
`rust_binder.ko` 当 consumer，因此漏审。

`0012` 让新增 SYSVIPC 布局只对 bindgen 隐藏，正常 C 编译仍保留真实字段；
`0013` 再由官方 `//common:kernel_aarch64_abi_update` 重建 ABI snapshot。相对
stock-compatible 基线的最终 `Module.symvers` 结果为：

```text
old symbols: 10351
new symbols: 10353
added:       init_ipc_ns, put_ipc_ns
removed:     0
CRC changed: 0
```

## 修复后的历史候选

strict ABI/KMI 构建、证书/release 检查和扩展 consumer 审查均通过：

```text
kernel release:              6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
Image SHA-256:               8dd40a7250932fd94f7023be68c624522da9983783c4236be4ff4d9824a1d284
Image size:                  42166784
vendor modules/imports:      466 / 22474
system_dlkm modules/imports: 103 / 5816
total modules/imports:       569 / 28290
stock rust_binder imports:   234, all matched
missing/CRC/provider:        0/0/0
strict ABI/KMI:              pass
```

最终验证摘要：

生成的 `Image` 和 stock-template boot 镜像位于被 `.gitignore` 忽略的
`kernel-work/artifacts/` 下，不随仓库发布。

修复后候选已通过一次 `fastboot boot` 实机复测：15 秒恢复 ADB，Android 完成
启动；模块数由首版的 669 恢复为 670，stock `rust_binder` 正常加载，dmesg 中
Rust KMI 错误、签名拒绝和 panic/oops 均为 0。Wi-Fi 已连接并 VALIDATED，蓝牙为
ON 且设备已连接，cellular 与两路 IMS 网络均有 VALIDATED 记录。PID/IPC namespace、
SYSVIPC、mqueue 和 devtmpfs smoke test 全部通过。

该候选没有有效 Xiaomi AVB 签名，只允许 `fastboot boot` 临时运行，禁止 flash，
禁止使用 slot B。正常重启会回到持久化 `boot_a`。

## 近五小时日常使用稳定性复核

2026-08-28 12:25 CST 对同一次临时启动进行了只读日志复核。最终 uptime 为
17707.54 秒，boot ID 未变化；670 个模块及 `rust_binder` 均保持加载。保留的
dmesg 窗口中没有 panic/oops/BUG、lockup/stall、内存破坏、KMI/签名错误、存储致命
错误或无线/基带子系统崩溃；内核 `oom_kill=0`。启动稳定后没有新的 Java/native
fatal、ANR、crash 类进程退出、当天 tombstone 或 ANR trace。最终 Wi-Fi、蓝牙、
cellular、IMS 和双卡注册状态正常，thermal status 为 0。

启动 07:31:03 曾有一次 `system_server` 的
`ComputerEngine.shouldFilterApplication` `StackOverflowError`，自动重启后
没有复发。这条其实已经存在于此前短测日志中，但先前总结漏记；相同调用栈也存在于
`r30-stock-compat` 的前一轮实机测试，所以不是本容器补丁新引入。另记录到三组
最终完成的 keystore watchdog 延迟，以及 15 个 Android 后台 LOW_MEMORY 回收；二者
均未形成内核 OOM 或 crash。

内核 ring buffer 因 vendor 日志量已覆盖中间时段，所以本结论能确认没有重启/panic
并覆盖启动早期和最终窗口，但不是对中间每一条非致命 kernel warning 的完整证明。

该结果是普通使用稳定性通过，不替代完整 Droidspaces 生命周期、过夜、休眠唤醒或
压力测试。

## 补丁顺序

## 可迁移构建流程

从仓库根目录执行以下步骤；脚本会根据自身位置找到 `kernel-work/`，不依赖仓库所在目录：

```sh
kernel-work/variants/r30-stock-containers/scripts/create-worktree.sh
kernel-work/variants/r30-stock-containers/scripts/build.sh
kernel-work/variants/r30-stock-containers/scripts/audit.sh
kernel-work/variants/r30-stock-containers/scripts/verify.sh
STOCK_BOOT=backup/your-stock-boot.img kernel-work/variants/r30-stock-containers/scripts/package-stock-boot.sh
```

`STOCK_BOOT` 必须指向你自己取得并校验过的 stock boot 镜像；stock 固件、设备备份、工具和构建产物不属于公开仓库。

`patches/common/series` 在 6 个 stock 兼容补丁之后包含：

```text
0007-enable-pid-namespaces.patch
0008-enable-sysvipc-posix-mqueue-kabi.patch
0009-export-ipc-namespace-symbols.patch
0010-update-gki-abi-for-container-ipc-state.patch
0011-enable-devtmpfs.patch
0012-preserve-stock-rust-kmi-for-sysvipc.patch
0013-update-abi-after-rust-kmi-preservation.patch
0014-enable-user-namespaces.patch
```

当前只完成了内核能力 smoke test；完整 Droidspaces 用户态创建/销毁流程、休眠唤醒
和长时间稳定性仍需按独立测试阶段验收。
