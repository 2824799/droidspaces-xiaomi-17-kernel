# Kernel build workspace layout

本目录是后续内核构建的唯一工作区。根目录不再堆放源码、临时文件和构建产物。

## 目录职责

```text
kernel-work/
├── upstream/       # 从 Git/repo 同步的原始仓库；只同步和读取，不直接修改
├── source-locks/   # 每次同步使用的 URL、branch、commit、manifest 和校验记录
├── variants/       # 永久保存的补丁、配置片段、构建脚本和变体说明
├── worktrees/      # 从 upstream 生成的可丢弃构建工作树；补丁只在这里应用
├── out/            # Bazel/Kleaf 等原始构建输出
├── artifacts/      # 通过验收后整理出的 Image、vmlinux、模块和 SHA256SUMS
├── logs/           # sync、patch、build、audit 和测试日志
├── cache/          # 可删除的下载/构建缓存
└── tools/          # 非源码工具和辅助程序
```

## 强制规则

1. `upstream/` 中的仓库保持原样，任何构建前后都必须保证 `git status --porcelain` 为空。
2. 不在 `upstream/` 中手工修改源码、配置或生成文件。
3. 所有有意修改永久保存到 `variants/<variant>/`：
   - 源码修改保存为按序编号的 `.patch`；
   - 内核选项保存为 config fragment；
   - Kleaf/Bazel 参数保存为脚本或文本配置；
   - commit、工具链、构建参数和输入哈希保存到 `metadata/`。
4. 每次构建重新创建 `worktrees/<variant>/`，然后按 `series` 应用补丁；工作树不是长期资料。
5. 如果调试时临时修改了工作树，必须先导出为补丁或配置片段，再重新创建工作树验证可复现性。
6. `out/`、`logs/` 和 `artifacts/` 按变体和时间分目录，不向项目根目录写构建文件。
7. 每个候选必须能从干净 `upstream` + `source-locks` + 对应 `variant` 完整复建。

## 当前构建线

当前公开变体为 `variants/r30-stock-containers/`。它针对 Xiaomi 17
(`pudding` / SM8850) 的 Android Common Kernel R30 GKI 基线，启用
Droidspaces 所需的 PID namespace、IPC namespace、SYSVIPC、POSIX mqueue、
devtmpfs 和 User Namespace，同时保留 stock module/KMI 兼容性审计流程。

构建所需的 Android 源码、stock boot 镜像、设备备份和生成产物均属于本地
工作资料，不提交到公开仓库；脚本通过自身位置定位 `kernel-work/`，因此
整个项目可以移动到其他目录后继续使用。
