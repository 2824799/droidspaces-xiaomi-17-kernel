# r30-control

目标：构建最小、纯净的 `android16-6.12-2026-03_r30` 控制内核，用于验证 stock 模块配对、DSI、移动数据和 IMS。

```text
r30-control/
├── patches/    # 编号补丁；初始应为空或仅含构建必需补丁
├── config/     # config fragments，不直接改 upstream defconfig
├── scripts/    # 创建工作树、应用补丁和调用构建的脚本
└── metadata/   # manifest/commit/toolchain/build 参数及输入哈希
```

约束：

- 不加入 Droidspaces 功能配置。
- 不加入 KernelSU。
- 不为了匹配文件名而事后修改 Image release 字符串。
- 第一目标是重现干净基线并闭合 GKI/system_dlkm/vendor_dlkm 模块关系。

