# Xiaomi 17 / HyperOS 4.0.0.9 platform profile

本分支用于记录 Xiaomi 17 `pudding` 在指定 stock 软件基线上的 Droidspaces 内核适配。

## Version identity

| Field | Value |
| --- | --- |
| Device | Xiaomi 17 |
| Model | `25113PN0EC` |
| Device codename | `pudding` |
| SoC / platform | Qualcomm SM8850 / `canoe` |
| Android target | Android 17（按本项目设备目标记录） |
| HyperOS package | HyperOS 4.0.0.9 card-flash package |
| Stock kernel release | `6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k` |
| Kernel source baseline | Android Common Kernel `android16-6.12-2026-03_r30` |

## Offline evidence

设备未连接时，从旧 stock `vendor_boot` 备份的 bootconfig 记录中复核到：

~~~text
swinfo.fingerprint=pudding:16/OS4.0.0.8.XPCCN:user
~~~

该记录只代表旧备份中的 stock 软件基线，可以确认产品代号和旧 HyperOS build 字符串为
`OS4.0.0.8.XPCCN`，不能覆盖你后来刷入的 HyperOS 4.0.0.9 卡刷包。当前分支按实际刷入
的卡刷包记录为 HyperOS 4.0.0.9。由于设备目前未连接，Android 17 的现场属性仍应在下次
连接后复核；旧 fingerprint 中的 `16` 段不能用来推翻你提供的 Android 17 版本信息。

~~~sh
adb shell getprop ro.build.version.release
adb shell getprop ro.build.display.id
adb shell getprop ro.build.version.incremental
adb shell getprop ro.build.fingerprint
~~~

本分支名称使用实际刷入的 HyperOS 版本：

`device/xiaomi17-android17-hyperos4.0.0.9`

## Kernel scope

本分支只描述上述设备和 stock 软件基线，不代表其他 Xiaomi 17 区域版本、不同 HyperOS
build 或不同 system/vendor/system_dlkm 组合可以直接复用。适配内容见：

- `kernel-work/variants/r30-stock-containers/`：补丁、构建脚本和审计脚本；
- [`docs/VALIDATION.md`](VALIDATION.md)：公开验证摘要；
- [`docs/README.md`](README.md)：完整历史工程归档。

生成的 boot 镜像、stock 固件、设备备份和设备唯一分区不属于公开仓库。修改 kernel
payload 会破坏 Xiaomi AVB 签名，任何镜像都只能按对应设备的安全边界处理。
