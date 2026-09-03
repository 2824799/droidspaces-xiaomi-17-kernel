# Xiaomi 17 / HyperOS 4.0.0.16 platform profile

本分支用于记录 Xiaomi 17 `pudding` 当前运行的 HyperOS 4.0.0.16 stock 软件基线，以及
此前 `4.0.0.9` 内核候选迁移到当前系统时需要满足的条件。

## Version identity

| Field | Value |
| --- | --- |
| Device | Xiaomi 17 |
| Model | `25113PN0EC` |
| Device codename | `pudding` |
| SoC / platform | Qualcomm SM8850 / `canoe` |
| Android release | `17` |
| Settings version | `4.0.0.16.XPCCNXM.D00` |
| HyperOS package | HyperOS 4.0.0.16 OTA package |
| Build ID | `CP2A.260605.016` |
| Build incremental | `OS4.0.0.16.XPCCNXM` |
| Build fingerprint | `Xiaomi/pudding/pudding:17/CP2A.260605.016/OS4.0.0.16.XPCCNXM:user/release-keys` |
| Security patch | `2026-08-01` |
| Stock kernel release | `6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k` |
| Kernel source baseline | Android Common Kernel `android16-6.12-2026-03_r30` |
| Previous validation baseline | Android 17 / HyperOS `4.0.0.9.XPCCNXM.D00` |

## Device-confirmed evidence

2026-09-03 设备通过 ADB 连接后，现场读取到以下系统属性：

~~~text
[ro.build.version.release]: 17
[ro.build.display.id]: CP2A.260605.016
[ro.build.version.incremental]: OS4.0.0.16.XPCCNXM
[ro.build.fingerprint]: Xiaomi/pudding/pudding:17/CP2A.260605.016/OS4.0.0.16.XPCCNXM:user/release-keys
[ro.build.version.security_patch]: 2026-08-01
~~~

旧 stock `boot_a` 备份仍记录过 `pudding:16/.../OS4.0.0.8.XPCCN:user`，那只是更早的旧
软件基线。当前设备实际运行的是 Android 17 / HyperOS 4.0.0.16。

~~~sh
adb shell getprop ro.build.version.release
adb shell getprop ro.build.display.id
adb shell getprop ro.build.version.incremental
adb shell getprop ro.build.fingerprint
~~~

本分支名称使用设备现场确认的完整软件版本：

`device/xiaomi17-android17-hyperos4.0.0.16-xpccnxm-d00`

## Boot binary comparison

2026-09-03 通过 root ADB 只读提取了当前活动槽 `_b` 的 `boot_b`，并与仓库外保存的
旧原厂 `boot_a` 进行了逐字节比较。两份文件均为 100663296 bytes、Android boot header
v4，header 页和内嵌 kernel 区域完全相同。完整文件只有 574 bytes 不同，差异位于
kernel 后的 AVB 元数据区域，内容反映旧的 `OS4.0.0.8` 与当前的 `OS4.0.0.16` 版本
描述。两份原厂 kernel 的 SHA-256 均为：

`574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2`

这说明本次系统升级没有改变原厂 kernel payload，但不等于旧的自定义 boot 镜像可以
直接刷写。自定义 payload 仍须嵌入当前 stock boot 模板，并重新处理当前 AVB 元数据；
当前分支已完成该候选在 HyperOS 4.0.0.16 设备上的持久化 `boot_b` 刷写和运行时
smoke test；完整的 `.16` 静态 system_dlkm/vendor module 复审仍沿用此前同一 kernel
release 的审计结果，未单独重新生成完整审计报告。当前设备测试候选 boot SHA-256 为：

`6066cebcbb1d1e6d0ec48db48ee5f45ea0c0aef14fedcd0ed279f12e6df2f633`

测试记录见 [`docs/RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.16.md`](RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.16.md)。

## Kernel scope

本分支只描述上述设备和 stock 软件基线，不代表其他 Xiaomi 17 区域版本、不同 HyperOS
build 或不同 system/vendor/system_dlkm 组合可以直接复用。适配内容见：

- `kernel-work/variants/r30-stock-containers/`：补丁、构建脚本和审计脚本；
- [`docs/VALIDATION.md`](VALIDATION.md)：公开验证摘要；
- [`docs/README.md`](README.md)：完整历史工程归档。

生成的 boot 镜像、stock 固件、设备备份和设备唯一分区不属于公开仓库。修改 kernel
payload 会破坏 Xiaomi AVB 签名，任何镜像都只能按对应设备的安全边界处理。此前发布的
内核资产及其使用条件见 [`docs/RELEASE_R30_STOCK_CONTAINERS_20260828.md`](RELEASE_R30_STOCK_CONTAINERS_20260828.md)。
