# R30 Droidspaces container variant

本目录从已通过实机无线/蜂窝验收的 `r30-stock-compat` 独立复制而来，不修改
`kernel-work/upstream/`，也不污染已验收的 `r30-stock-compat`。

## 配置边界

已启用：

```text
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_DEVTMPFS=y
```

刻意保持关闭：

```text
CONFIG_DEVTMPFS_MOUNT=n
CONFIG_USER_NS=n
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

## 修复后正式候选

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

产物：

```text
/home/nahida/agents/tmp/kernel-work/artifacts/r30-stock-containers/20260827T230746Z-rust-kmi-fixed/
/home/nahida/agents/tmp/kernel-work/artifacts/r30-stock-containers-stock-template/20260827T232346Z-rust-kmi-fixed-stock-template/boot-r30-stock-containers-stock-template.img
boot size:    100663296
boot SHA-256: 6348a94928c9298135fa07c2f44c89b36731af21a3bfcfabc53f99d5aedfdbaf
```

修复后候选已通过一次 `fastboot boot` 实机复测：15 秒恢复 ADB，Android 完成
启动；模块数由首版的 669 恢复为 670，stock `rust_binder` 正常加载，dmesg 中
Rust KMI 错误、签名拒绝和 panic/oops 均为 0。Wi-Fi 已连接并 VALIDATED，蓝牙为
ON 且设备已连接，cellular 与两路 IMS 网络均有 VALIDATED 记录。PID/IPC namespace、
SYSVIPC、mqueue 和 devtmpfs smoke test 全部通过。

实机日志：

```text
/home/nahida/agents/tmp/kernel-work/logs/r30-stock-containers/device-tests/20260827T233007Z-rust-kmi-fixed-device-test/
```

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

```text
/home/nahida/agents/tmp/kernel-work/logs/r30-stock-containers/device-tests/20260828T041954Z-morning-stability-review/
```

该结果是普通使用稳定性通过，不替代完整 Droidspaces 生命周期、过夜、休眠唤醒或
压力测试。

## 补丁顺序

`patches/common/series` 在 6 个 stock 兼容补丁之后包含：

```text
0007-enable-pid-namespaces.patch
0008-enable-sysvipc-posix-mqueue-kabi.patch
0009-export-ipc-namespace-symbols.patch
0010-update-gki-abi-for-container-ipc-state.patch
0011-enable-devtmpfs.patch
0012-preserve-stock-rust-kmi-for-sysvipc.patch
0013-update-abi-after-rust-kmi-preservation.patch
```

当前只完成了内核能力 smoke test；完整 Droidspaces 用户态创建/销毁流程、休眠唤醒
和长时间稳定性仍需按独立测试阶段验收。
