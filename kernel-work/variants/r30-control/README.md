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

## 设备 boot 候选

Kleaf 导出的 64 MiB `boot.img` 是通用 GKI 构建产物，不能直接视为小米 17
设备候选。设备候选必须以已校验的 96 MiB 原厂 `boot_a.img` 为模板，只替换
其中的 kernel，并在重打包后再次解包核验。

```bash
/home/nahida/agents/tmp/kernel-work/variants/r30-control/scripts/package-stock-boot.sh
```

该脚本只借用已启动手机的 ARM64 环境运行历史 MagiskBoot，不读取或写入任何
设备分区，不重启设备。输出位于：

```text
/home/nahida/agents/tmp/kernel-work/artifacts/r30-control-stock-template/latest/
```

候选仅允许在解锁 bootloader 上使用 `fastboot boot` 临时测试，禁止刷写。替换
kernel 后无法保留有效的小米 AVB 加密签名；保留 `AVB0`/`AVBf` 外形不代表
签名有效。
