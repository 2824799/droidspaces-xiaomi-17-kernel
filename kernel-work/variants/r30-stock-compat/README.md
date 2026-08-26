# R30 stock compatibility variant

该 variant 以只读上游 `android16-6.12-2026-03_r30` 为基线，只在独立 worktree
应用 R31 中 4 个 Xiaomi 相关官方提交。目标是匹配当前 stock 的 466 个
`vendor_ramdisk` 模块，不修改 `kernel-work/upstream/`。

## 官方补丁链

按 `patches/common/series` 顺序应用：

1. `aa795bd04bdf`：CMA/DMA allocation latency hooks；
2. `8aa6935b068b`：direct reclaim latency hooks；
3. `4faf781e81fc`：导出 `try_to_free_pages`；
4. `bc587ccd5d16`：更新 Xiaomi KMI symbol list。

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

## 2026-08-26 结果

~~~text
Image SHA-256:          b501d87e6b62234494d7df2d87cc533ccc8d729325438f082f32d985d0949c72
Module.symvers SHA-256: af77d02d0a3e1a7581e8cc416f3b05340364e6d3f3abc01cc2dfa119d09923ab
modules audited:        466
imports checked:        22474
missing:                0
CRC mismatch:           0
provider conflict:      0
audit_pass:             true
boot size:              100663296 bytes
boot SHA-256:           d06380f9ea23cf834cf5f951bbbf7cae8e171ece44117b000c6e0df0ba0829dc
~~~

本地重打包器已用旧 R30 Image 证明与已归档 MagiskBoot 输出逐字节相同。成品包含
构建元数据、466 模块审查报告、补丁来源和补丁哈希。

## 安全边界

- 当前候选尚未实机启动。
- KernelSU LKM 配对尚未通过。
- 修改 kernel 后不具有有效小米 AVB 签名。
- 只允许明确授权后的 `fastboot boot` 临时测试。
- 禁止 flash；禁止使用空的 slot B；未经授权不重启或操作手机。
