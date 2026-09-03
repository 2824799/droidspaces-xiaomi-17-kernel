# R30 stock-containers release record

This release publishes the retained `r30-stock-containers` Android ARM64 kernel
Image from the August 28, 2026 audited build. The asset is a kernel payload, not
a complete Xiaomi flashing package.

## Asset identity

```text
Variant:       r30-stock-containers
Kernel:        6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
Image size:    42232320 bytes
Image SHA-256: 9645dec7d368198597372c64fcb45b9bd525238a42e7e8c8098911a2e4040aae
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

This retained August 28 asset was not independently boot-tested after that build;
the separate August 27 device-smoke-tested Image recorded in the engineering
archive has SHA-256 `8dd40a7250932fd94f7023be68c624522da9983783c4236be4ff4d9824a1d284`,
but that binary is no longer retained locally.

## Use conditions

- Use only on the matching Xiaomi 17 `pudding` hardware and the matching
  Android 17 / HyperOS 4.0.0.9 stock module baseline unless a new audit is done.
- HyperOS 4.0.0.16 has the same stock kernel release, but this release has not
  been validated against its complete module and boot metadata set.
- The Image must be repackaged into a matching stock `boot.img`; do not write the
  raw Image directly to a partition.
- The modified payload does not have a valid Xiaomi AVB signature. Use only
  temporary `fastboot boot` testing on an unlocked bootloader.
- Do not use `fastboot flash`, do not distribute it as a generic installer, and
  keep verified stock backups and device-unique partitions outside the repository.

The published SHA-256 file is the integrity check for the release asset.
