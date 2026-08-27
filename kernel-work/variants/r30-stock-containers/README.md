# R30 Droidspaces container-stage variant

本目录从已通过实机无线/蜂窝验收的 `r30-stock-compat` 独立复制而来，不修改原始
`kernel-work/upstream/`，也不污染 `r30-stock-compat`。

## 当前阶段

当前只启用第一阶段：

```text
CONFIG_PID_NS=y
```

R30 的 Kconfig 默认值本来就是 `y`，但 GKI defconfig 显式写了
`# CONFIG_PID_NS is not set`。因此本阶段补丁只删除这个显式关闭项；没有修改
调度结构、KMI 符号、模块签名、RFKILL 或任何无线/蜂窝代码。

当前阶段未启用：

```text
CONFIG_IPC_NS
CONFIG_SYSVIPC
CONFIG_POSIX_MQUEUE
CONFIG_DEVTMPFS
CONFIG_USER_NS
CONFIG_CGROUP_DEVICE
```

## 构建结果

阶段 1 已完成 strict KMI 构建、stock release/certificate 检查和 466 个 vendor
ramdisk 模块审计。候选尚未进行手机实机启动测试。

```text
Image SHA-256: 7532f7ceecce2ac010cf5d43abce567f32687ee8e7210191c91123a50d326328
Image size:   42097152 bytes
kernel release: 6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
modules audited: 466
imports checked: 22474
missing/crc/provider conflicts: 0/0/0
```

对应产物目录：

```text
/home/nahida/agents/tmp/kernel-work/artifacts/r30-stock-containers/20260827T140700Z-stage1-pid-ns-v2/
```

下一步打包候选只允许 `fastboot boot` 临时启动；在获得明确实机测试授权前不重启、
不刷写、不操作当前正常工作的手机。

## 补丁顺序

当前 `patches/common/series` 包含原有 6 个兼容补丁和本阶段的：

```text
0007-enable-pid-namespaces.patch
```

后续 SYSVIPC/KABI、符号导出和 DEVTMPFS 改动必须继续使用独立提交，不能把多个
阶段压成一个不可二分的补丁。
