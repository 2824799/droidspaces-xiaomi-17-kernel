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

### 2026-08-26 实机结果

96 MiB 原厂模板候选已通过 `fastboot boot` 实机测试。设备持续黑屏且未出现
ADB，用户随后手动进入 fastboot；进入前瞬间观察到绿色小米 Logo。恢复后的
pstore 确认 R30 内核实际运行到至少约 10.72 秒，但没有捕获明确 panic/Oops。

已确认的运行时不兼容包括：

- 原 `init_boot_a` 中的 KernelSU 报 `no symbol version for module_layout`；
- `mi_memory_monitor.ko` 因缺少
  `__tracepoint_android_vh_mm_direct_reclaim_end` 加载失败；
- stock 运行时 798 个 Android tracepoint 中有 8 个不在 R30 输出；
- `arm_smmu`/TBU 出现 probe 失败与超时，随后多个设备等待
  `apps-smmu` supplier。

因此 R30 原样不能作为当前设备的可启动控制基线。绿色 Logo 只记录为显示
handoff 现象，不能单独归因于显示驱动。A 槽关键分区哈希未改变，设备已恢复
stock。
