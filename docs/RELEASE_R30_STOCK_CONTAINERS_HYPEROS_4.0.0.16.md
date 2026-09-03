# R30 stock-containers / HyperOS 4.0.0.16 release record

This release contains the complete Android header-v4 boot image tested on a
Xiaomi 17 `pudding` after a persistent write to the active `boot_b` partition.
It also contains the kernel Image used to assemble that boot image.

## Device and system

```text
Device:          Xiaomi 17
Model:           25113PN0EC
Codename:        pudding
Platform:        Qualcomm SM8850 / canoe
Android:         17
HyperOS:         4.0.0.16.XPCCNXM
Build ID:        CP2A.260605.016
Fingerprint:     Xiaomi/pudding/pudding:17/CP2A.260605.016/OS4.0.0.16.XPCCNXM:user/release-keys
Kernel release: 6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
Slot tested:     _b
```

## Asset identity

```text
Kernel Image size:    42232320 bytes
Kernel Image SHA-256: 9645dec7d368198597372c64fcb45b9bd525238a42e7e8c8098911a2e4040aae
Boot image size:      100663296 bytes
Boot image SHA-256:   6066cebcbb1d1e6d0ec48db48ee5f45ea0c0aef14fedcd0ed279f12e6df2f633
Boot format:          Android header version 4, 4096-byte pages, no ramdisk
```

## Persistent device test

On September 3, 2026, the boot image was written to `boot_b` on the unlocked
test device. The partition was read back after reboot and matched the published
boot image byte-for-byte. The device remained on slot `_b` and completed Android
boot successfully.

Passed checks:

- `sys.boot_completed=1`;
- kernel release and build timestamp matched the candidate;
- `CONFIG_PID_NS=y`, `CONFIG_IPC_NS=y`, `CONFIG_SYSVIPC=y`,
  `CONFIG_POSIX_MQUEUE=y`, `CONFIG_DEVTMPFS=y`, and `CONFIG_USER_NS=y`;
- stock `rust_binder.ko` loaded;
- `unshare -Ur` returned success;
- Wi-Fi reached `Supplicant state: COMPLETED`;
- voice and data registration reached `IN_SERVICE`;
- boot ID stayed unchanged during a 30-second stability check;
- no panic, oops, KMI/CRC mismatch, module rejection, or fatal kernel error
  was observed.

A non-fatal DRM warning with a `drm_crtc_set_max_vblank_count` call trace was
present in dmesg; it did not cause a reboot or prevent display/system startup.
This release does not claim long-term stress, suspend/resume, call/SMS, or
universal regional compatibility.

## Use conditions

- Target only Xiaomi 17 `pudding` hardware with the matching Android 17 /
  HyperOS 4.0.0.16 software and module set.
- The published boot image is a complete boot-format image, but it is still a
  device-specific research artifact. Do not treat it as a generic installer.
- Keep a verified stock backup and know how to restore the matching stock boot
  image before modifying any device.
- The modified kernel payload is not signed by Xiaomi's production AVB key.
  The successful test on this device does not prove compatibility with another
  region, build, or bootloader policy.
- Do not modify `vbmeta`, `vendor_boot`, `init_boot`, calibration partitions,
  modem/NV partitions, or other device-unique partitions based on this release.
