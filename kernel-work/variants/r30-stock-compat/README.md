# R30 stock compatibility variant

该 variant 以只读上游 `android16-6.12-2026-03_r30` 为基线，只在独立 worktree
应用 R31 中 4 个 Xiaomi 相关官方提交，并用第 5 个本地非功能补丁固定 stock
`system_dlkm` 所需的 release identity。目标是同时匹配当前 stock 的
`vendor_ramdisk` ABI 和 `system_dlkm` 模块目录，不修改 `kernel-work/upstream/`。

## 官方补丁链

按 `patches/common/series` 顺序应用：

1. `aa795bd04bdf`：CMA/DMA allocation latency hooks；
2. `8aa6935b068b`：direct reclaim latency hooks；
3. `4faf781e81fc`：导出 `try_to_free_pages`；
4. `bc587ccd5d16`：更新 Xiaomi KMI symbol list。
5. 本地 release pairing：设置 `SCMVERSION=-gb1493ec68d4a-abogki514973465`。

仅前两个补丁不会让新符号进入 trim 后的 `Module.symvers`；遗漏第三项时，第四项
会触发 strict KMI 的 `try_to_free_pages` ksymtab 错误。不得使用空 hook 或伪造
CRC 代替这条官方链。完整来源与 SHA-256 位于 `metadata/`。

## 可复现流程

~~~bash
/home/nahida/agents/tmp/kernel-work/variants/r30-stock-compat/scripts/create-worktree.sh
JOBS=16 /home/nahida/agents/tmp/kernel-work/variants/r30-stock-compat/scripts/build.sh
/home/nahida/agents/tmp/kernel-work/variants/r30-stock-compat/scripts/verify.sh
/home/nahida/agents/tmp/kernel-work/variants/r30-stock-compat/scripts/audit.sh
/home/nahida/agents/tmp/kernel-work/variants/r30-stock-compat/scripts/package-stock-boot-local.sh
~~~

生成目录分别位于 `kernel-work/worktrees/`、`out/`、`logs/` 和 `artifacts/`，均不
提交到本地 Git。

## 2026-08-27 release 配对修复

四项官方补丁候选能够启动 Android，但其 `uname -r` 为
`6.12.69-android16-6-4k`。stock `system_dlkm` 模块位于：

~~~text
/system_dlkm/lib/modules/6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
~~~

Android 因 release 目录不匹配跳过该模块树，运行模块比 stock 少 91 个，缺少
`bluetooth`、`cfg80211`、`mac80211`、`qca_cld3_peach_v2`、`rfkill`、`wwan`
等，因此 Wi-Fi、蓝牙、热点、移动数据和通话同时不可用。这不是 CRC/KMI 问题；
vendor ramdisk、system_dlkm、vendor_dlkm 的扩展符号审查均无缺失或 CRC 冲突。

首次加入 `workspace_status.json` 后仍未生效，是因为构建机没有 `repo` 命令，构建
脚本也没有把锁定 manifest 传给 Kleaf，实际生成的是
`STABLE_SCMVERSIONS {}`。`build.sh` 现已显式传入
`source-locks/r30/checked-out-manifest.xml`，并在构建前拒绝空的 common
SCMVERSION。修复后的结果：

~~~text
kernel release:         6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
Image SHA-256:          e2450f4f7ead1b1c9143f6d0af44aec293d0c7e039ec0ca276fb8550b7432ced
Module.symvers SHA-256: af77d02d0a3e1a7581e8cc416f3b05340364e6d3f3abc01cc2dfa119d09923ab
modules audited:        466
imports checked:        22474
missing:                0
CRC mismatch:           0
provider conflict:      0
audit_pass:             true
boot size:              100663296 bytes
boot SHA-256:           21ca6f1b7ecb6dd3b7831df98f29c807709775f8bee4df2a8fd2392952253a67
~~~

本地重打包器已用旧 R30 Image 证明与已归档 MagiskBoot 输出逐字节相同。成品包含
构建元数据、466 模块审查报告、补丁来源和补丁哈希。

## 安全边界

- release 配对前候选已启动，但射频模块树因目录名不匹配而未加载。
- release 配对后的新候选尚未实机启动。
- KernelSU LKM 配对尚未通过。
- 修改 kernel 后不具有有效小米 AVB 签名。
- 只允许明确授权后的 `fastboot boot` 临时测试。
- 禁止 flash；禁止使用空的 slot B；未经授权不重启或操作手机。
