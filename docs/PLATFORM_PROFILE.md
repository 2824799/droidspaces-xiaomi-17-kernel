# Xiaomi 17 / HyperOS 4.0.0.9 platform profile

本分支用于记录 Xiaomi 17 `pudding` 在指定 stock 软件基线上的 Droidspaces 内核适配。

## Version identity

| Field | Value |
| --- | --- |
| Device | Xiaomi 17 |
| Model | `25113PN0EC` |
| Device codename | `pudding` |
| SoC / platform | Qualcomm SM8850 / `canoe` |
| Android release | `17` |
| Settings version | `4.0.0.9.XPCCNXM.D00` |
| HyperOS package | HyperOS 4.0.0.9 card-flash package |
| Build ID | `CP2A.260605.016` |
| Build incremental | `OS4.0.0.9.XPCCNXM` |
| Build fingerprint | `Xiaomi/pudding/pudding:17/CP2A.260605.016/OS4.0.0.9.XPCCNXM:user/release-keys` |
| Security patch | `2026-08-01` |
| Stock kernel release | `6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k` |
| Kernel source baseline | Android Common Kernel `android16-6.12-2026-03_r30` |

## Device-confirmed evidence

2026-09-03 设备通过 ADB 连接后，现场读取到以下系统属性：

~~~text
[ro.build.version.release]: 17
[ro.build.display.id]: CP2A.260605.016
[ro.build.version.incremental]: OS4.0.0.9.XPCCNXM
[ro.build.fingerprint]: Xiaomi/pudding/pudding:17/CP2A.260605.016/OS4.0.0.9.XPCCNXM:user/release-keys
[ro.build.version.security_patch]: 2026-08-01
~~~

旧 stock `vendor_boot` 备份仍记录过 `pudding:16/OS4.0.0.8.XPCCN:user`，那只是升级前的旧
软件基线。它不能覆盖当前设备实际运行的 Android 17 / HyperOS 4.0.0.9 系统。

~~~sh
adb shell getprop ro.build.version.release
adb shell getprop ro.build.display.id
adb shell getprop ro.build.version.incremental
adb shell getprop ro.build.fingerprint
~~~

本分支名称使用设备现场确认的完整软件版本：

`device/xiaomi17-android17-hyperos4.0.0.9-xpccnxm-d00`

## Kernel scope

本分支只描述上述设备和 stock 软件基线，不代表其他 Xiaomi 17 区域版本、不同 HyperOS
build 或不同 system/vendor/system_dlkm 组合可以直接复用。适配内容见：

- `kernel-work/variants/r30-stock-containers/`：补丁、构建脚本和审计脚本；
- [`docs/VALIDATION.md`](VALIDATION.md)：公开验证摘要；
- [`docs/README.md`](README.md)：完整历史工程归档。

生成的 boot 镜像、stock 固件、设备备份和设备唯一分区不属于公开仓库。修改 kernel
payload 会破坏 Xiaomi AVB 签名，任何镜像都只能按对应设备的安全边界处理。
