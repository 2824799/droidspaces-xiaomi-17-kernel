# R30 stock-containers release record

This release publishes the retained `r30-stock-containers` Android ARM64 kernel
Image and a complete Android header-v4 `boot.img` assembled from that Image.
The boot image is a device-specific research artifact, not a signed Xiaomi
flashing package.

## Asset identity

```text
Variant:       r30-stock-containers
Kernel:        6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
Image size:    42232320 bytes
Image SHA-256: 9645dec7d368198597372c64fcb45b9bd525238a42e7e8c8098911a2e4040aae
Boot image:    100663296 bytes
Boot SHA-256:  1bb3a5557a3300b4e8fca819c25064ffec9eb1cfd234b9b725c6a24128de7f6c
Base:          Android Common Kernel android16-6.12-2026-03_r30

Target device: Xiaomi 17 / 25113PN0EC / pudding
Platform:      Qualcomm SM8850 / canoe
Validated baseline: Android 17 / HyperOS 4.0.0.9.XPCCNXM.D00
```

## What was verified

- Strict ABI/KMI check passed.
- 466 vendor modules and 103 stock `system_dlkm` modules were audited.
- 28,290 imports were checked with zero missing symbols, CRC mismatches, or
  provider conflicts.
- The stock `rust_binder.ko` consumer's 234 imports matched.
- The build uses `CONFIG_PID_NS=y`, `CONFIG_IPC_NS=y`, `CONFIG_SYSVIPC=y`,
  `CONFIG_POSIX_MQUEUE=y`, `CONFIG_DEVTMPFS=y`, and `CONFIG_USER_NS=y`.

The R30 User Namespace solution passed a historical Xiaomi 17 `pudding` device
smoke test on August 27, 2026 using Image SHA-256
`8dd40a7250932fd94f7023be68c624522da9983783c4236be4ff4d9824a1d284` and boot
candidate SHA-256 `6348a94928c9298135fa07c2f44c89b36731af21a3bfcfabc53f99d5aedfdbaf`.
That validation covered Android boot, stock module loading, Wi-Fi, Bluetooth,
cellular/IMS, PID/IPC namespace, SYSVIPC, mqueue, devtmpfs, and KSU root.

The published August 28 assets are the retained audited rebuild: its Image SHA-256
is `9645dec7d368198597372c64fcb45b9bd525238a42e7e8c8098911a2e4040aae` and its
complete boot SHA-256 is `1bb3a5557a3300b4e8fca819c25064ffec9eb1cfd234b9b725c6a24128de7f6c`.
The August 28 rebuild passed the complete static module audit but was not independently
boot-tested after that build; the historical device-tested hashes above are retained
as the validation record and are not available as downloadable binaries.

## Use conditions

- Use only on the matching Xiaomi 17 `pudding` hardware and the matching
  Android 17 / HyperOS 4.0.0.9 stock module baseline unless a new audit is done.
- HyperOS 4.0.0.16 has the same stock kernel release, but this release has not
  been validated against its complete module and boot metadata set.
- The published `boot.img` is already a complete header-v4 image for the recorded
  Android 17 / HyperOS 4.0.0.9-era stock boot layout. The raw Image is also
  provided separately for repackaging against another stock boot template.
- Do not write the raw Image directly to a partition.
- The modified payload does not have a valid Xiaomi AVB signature. Use only
  temporary `fastboot boot` testing on an unlocked bootloader.
- Even though the published boot asset is a complete boot image, do not use
  `fastboot flash`; do not distribute it as a generic installer, and
  keep verified stock backups and device-unique partitions outside the repository.

The published SHA-256 file is the integrity check for the release asset.
