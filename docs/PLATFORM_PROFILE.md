# Xiaomi 17 / HyperOS 4.0.0.26 platform profile

本分支记录 Xiaomi 17 `pudding` 的 HyperOS 4.0.0.26 stock 软件基线，以及此前
`r30-stock-containers` 内核候选迁移到该版本时需要满足的条件。

## Version identity

| Field | Value |
| --- | --- |
| Device | Xiaomi 17 |
| Model | `25113PN0EC` |
| Device codename | `pudding` |
| SoC / platform | Qualcomm SM8850 / `canoe` |
| Android release | `17` (SDK 37) |
| Settings version | `4.0.0.26.XPCCNXM.D00` |
| OEM package | `pudding-ota_full-OS4.0.0.26.XPCCNXM-user-17.0-9c0a5c052e.zip` |
| Build ID | `CP2A.260605.016` |
| OTA POST-build label | `17OS4.0.260905.065436767.QCPECN.S` |
| OTA POST-build fingerprint | `Xiaomi/pudding/pudding:17/CP2A.260605.016/17OS4.0.260905.065436767.QCPECN.S:user/release-keys` |
| Security patch | `2026-08-01` |
| Stock kernel release | `6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k` |
| Stock kernel payload SHA-256 | `574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2` |
| Kernel source baseline | Android Common Kernel `android16-6.12-2026-03_r30` |
| Previous baselines | HyperOS `4.0.0.16.XPCCNXM.D00`, HyperOS `4.0.0.9.XPCCNXM.D00` |

## Evidence source for this version

`.16` 与 `.9` 的身份是设备现场读取的 `ro.build.*`。本次 `.26` 的身份来自 OEM 完整
OTA 包本身：payload manifest、各分区 `build.prop` 与 `vbmeta` 中的 AVB 描述符。OTA
元数据给出的 post-build 为：

~~~text
post-build=Xiaomi/pudding/pudding:17/CP2A.260605.016/17OS4.0.260905.065436767.QCPECN.S:user/release-keys
post-build-incremental=17OS4.0.260905.065436767.QCPECN.S
post-sdk-level=37
post-security-patch-level=2026-08-01
pre-device=pudding
~~~

该包内部的分区标签并不统一：`product`、`mi_ext`、`mi_product` 使用
`OS4.0.0.26.XPCCNXM`，而 `boot`、`vendor`、`vendor_boot`、`odm`、
`system_dlkm`、`dtbo` 等内核相关分区仍是上一轮的 `OS4.0.0.25.XPCCN` 标签。设备
刷入后现场读取的 `ro.build.*` 会在设备可用时补录到本文件。

~~~sh
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.incremental
adb shell getprop ro.build.fingerprint
adb shell getprop ro.build.version.security_patch
~~~

本分支名称使用该 OTA 的设备现场版本号：

`device/xiaomi17-android17-hyperos4.0.0.26-xpccnxm-d00`

## Boot binary comparison

从 `.26` OTA 提取的 stock `boot` 分区，与 `.16` 分支上从设备活动槽只读提取的
`boot_b` 逐字节比较结果：

~~~text
identical size:      100663296 bytes (both)
boot header:         version 4, 4096-byte pages, header size 1584, ramdisk size 0
kernel offset:       4096 (both)
kernel size:         41507328 bytes (both)
kernel SHA-256:      574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2 (both)
differing bytes:     543, all inside the vbmeta blob after the kernel
difference content:  the embedded version label, OS4.0.0.16.XPCCN -> OS4.0.0.25.XPCCN
~~~

同样的结论在 `.9` 到 `.16` 的升级中已经出现过一次。两次系统升级都没有改变原厂
kernel payload，因此 `.26` 不需要重新编译内核：只需把已经审计过的 Image 嵌入
`.26` 的 stock boot 模板，并沿用该模板的 AVB 元数据重新打包。

`.26` 候选 boot 的 SHA-256 为：

`b974c356caf877d3c30893a117b83a2c69955f14ed088ead98641bd32207ba19`

该候选已完成针对 `.26` 模块树的完整静态审计与结构校验，但尚未做上机测试。测试记录与
完整数据见
[`docs/RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.26.md`](RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.26.md)。

## Module baseline change

`.26` 的模块树直接从 OTA 包解出，比沿用手工备份的旧基线更贴近当前系统：

~~~text
vendor modules:      466, none added or removed, 415 identical, 51 changed
system_dlkm modules: 103, all identical
~~~

51 个变化的 vendor 模块在针对候选内核的导入审计中全部通过；`system_dlkm` 的 103 个
模块（其中包含 `rust_binder.ko`）与旧基线完全一致。

## Kernel scope

本分支只描述上述设备和 stock 软件基线，不代表其他 Xiaomi 17 区域版本、不同 HyperOS
build 或不同 system/vendor/system_dlkm 组合可以直接复用。适配内容见：

- `kernel-work/variants/r30-stock-containers/`：补丁、构建脚本、审计脚本与打包脚本；
- [`docs/VALIDATION.md`](VALIDATION.md)：公开验证摘要；
- [`docs/README.md`](README.md)：完整历史工程归档。

生成的 boot 镜像、stock 固件、设备备份和设备唯一分区不属于公开仓库。修改 kernel
payload 会破坏 Xiaomi AVB 签名，任何镜像都只能按对应设备的安全边界处理。此前发布的
内核资产及其使用条件见
[`docs/RELEASE_R30_STOCK_CONTAINERS_20260828.md`](RELEASE_R30_STOCK_CONTAINERS_20260828.md)
与
[`docs/RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.16.md`](RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.16.md)。

