# R30 Droidspaces container-stage variant

本目录从已通过实机无线/蜂窝验收的 `r30-stock-compat` 独立复制而来，不修改原始
`kernel-work/upstream/`，也不污染 `r30-stock-compat`。

## 当前阶段

最小容器配置阶段已全部启用：

```text
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_DEVTMPFS=y
```

R30 的 Kconfig 默认值本来就是 `y`，但 GKI defconfig 显式写了
`# CONFIG_PID_NS is not set`，所以 PID namespace 补丁只删除该覆盖项。
`CONFIG_IPC_NS` 依赖 `SYSVIPC || POSIX_MQUEUE`，在后两项启用后由 Kconfig
自动取默认值 `y`，没有向 defconfig 写入冗余项。

SYSVIPC 的 `sysvsem`/`sysvshm` 被放入 `task_struct` 中原有的 28 字节
对齐空洞。最终 DWARF 布局保持：

```text
sizeof(task_struct)=5184
rt_priority=160
sysvsem=164
sysvshm=172
sched_entity(se)=192
```

`rust_binder.ko` 所需的真实 `init_ipc_ns` 和 `put_ipc_ns` 已导出，但没有
加入公开稳定 GKI KMI symbol list。ABI snapshot 由官方
`//common:kernel_aarch64_abi_update` 目标生成，没有手工写 ABI 或 CRC。

刻意保持关闭：

```text
CONFIG_DEVTMPFS_MOUNT
CONFIG_USER_NS
CONFIG_CGROUP_DEVICE
```

## 构建结果

最终阶段已完成 strict KMI 构建、stock release/certificate 检查和 466 个 vendor
ramdisk 模块审计。候选尚未进行手机实机启动测试。

```text
Image SHA-256: 460c4ee4d025bb9fa042068c5ebc8418d1882079529f4951509b8d90bce97232
Image size:   42166784 bytes
kernel release: 6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
modules audited: 466
imports checked: 22474
missing/crc/provider conflicts: 0/0/0
strict ABI/KMI build: pass
```

对应产物目录：

```text
/home/nahida/agents/tmp/kernel-work/artifacts/r30-stock-containers/20260827T152000Z-final-containers/
```

下一步打包候选只允许 `fastboot boot` 临时启动；在获得明确实机测试授权前不重启、
不刷写、不操作当前正常工作的手机。

## 补丁顺序

当前 `patches/common/series` 包含原有 6 个兼容补丁和：

```text
0007-enable-pid-namespaces.patch
0008-enable-sysvipc-posix-mqueue-kabi.patch
0009-export-ipc-namespace-symbols.patch
0010-update-gki-abi-for-container-ipc-state.patch
0011-enable-devtmpfs.patch
```

最小配置补丁链已经完成。下一步是独立的实机 `fastboot boot` 验收；该步骤
尚未执行，不能用静态审查结果代替无线、蜂窝和容器生命周期测试。
