# 下一阶段：Droidspaces 容器配置

记录日期：2026-08-27（Asia/Shanghai）

## 已冻结的可用基线

后续工作必须从当前已经通过实机验收的 r30-stock-compat 提交复制为新 variant，
不能直接继续修改本目录的基线补丁。当前基线包含：

1. Android Common R30；
2. 四项官方 R31 Xiaomi 兼容提交；
3. stock system_dlkm release identity；
4. stock system_dlkm 公开模块签名证书。

最终临时启动候选：

~~~text
boot SHA-256: aafd350bbd00a2c7a2267d04e3d1745b08aa6cf28938514cc80f7ea5fbdac71d
Image SHA-256: 7c4c3f13a04ae5a63901f91b270070c0c8cd6d40a037ff042baa9d3386f71cdd
kernel release: 6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
loaded modules: 670 / stock 670
~~~

实机已确认 Wi-Fi、蓝牙、双卡注册、IMS 和蜂窝 Internet 网络恢复；用户确认当前功能
看起来全部可用。本轮没有主动拨号、发短信或切换热点。

## 容器目标配置

Droidspaces 当前需要启用：

~~~text
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_DEVTMPFS=y
~~~

本轮不主动启用：

~~~text
CONFIG_USER_NS=n
CONFIG_CGROUP_DEVICE=n
~~~

RFKILL 在已验证基线中作为 stock 模块正常工作，不再把 CONFIG_RFKILL=y 混入容器
配置变化。KernelSU、其他 root 改动和额外 Android vendor hook 也不得与第一轮容器
配置混在一起。

## 实施顺序

建议建立独立 variant，例如 r30-stock-containers，并按以下阶段提交：

1. 只启用 PID_NS 与 IPC_NS；
2. 启用 SYSVIPC 与 POSIX_MQUEUE，同时应用对应 task_struct KABI hole 规则；
3. 补齐容器运行所需的 init_ipc_ns、put_ipc_ns 导出，并重新做 KMI strict 检查；
4. 启用 DEVTMPFS；
5. 最后才处理 KernelSU 或其他运行时变量。

如果希望一次生成完整容器候选，也必须保留上述配置与补丁的独立提交，方便二分定位。

## 每阶段硬性验收

每个阶段必须重新完成：

- Kleaf strict KMI 构建；
- 466 个 vendor_ramdisk 模块导入、CRC、provider 审查；
- system_dlkm 和 vendor_dlkm 扩展审查；
- stock release identity 与 stock module certificate 内建检查；
- 96 MiB stock boot 模板结构检查；
- 只使用 fastboot boot 临时启动；
- sys.boot_completed=1；
- /proc/modules 预期仍为 670，除非配置变化有明确且已解释的模块内建差异；
- Wi-Fi、蓝牙、双卡注册、两路 IMS 和蜂窝 Internet 网络复验；
- Droidspaces 容器创建、启动、停止和销毁测试。

任何阶段出现模块数量下降、protected symbol 拒绝、Wi-Fi/蓝牙失效、IMS 网络消失或
蜂窝 Internet 不再 VALIDATED，应立即停止，不叠加下一组配置。

## 安全边界

- 不修改 kernel-work/upstream；
- 不覆盖已验证的 r30-stock-compat；
- 不写入 boot、init_boot 或 slot B；
- 修改后的 boot 没有有效 Xiaomi AVB 签名，只允许 fastboot boot；
- 不主动拨号、发短信或修改 APN/IMS/radio 配置。
