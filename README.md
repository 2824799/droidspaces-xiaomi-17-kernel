# Droidspaces Xiaomi 17 Kernel Work

Reproducible kernel patches and validation notes for enabling Android container
primitives on the Xiaomi 17 (`pudding`, Qualcomm SM8850 / `canoe`) with the
Android Common Kernel `android16-6.12-2026-03_r30` GKI baseline.

This repository is intentionally a source-and-process project. It contains the
patch series, source locks, build/audit scripts, and public validation notes. The
repository tree does not contain Android source checkouts, stock firmware, device
backups, private keys, or generated kernel images; finished, device-tested boot
images are published separately as GitHub Releases.

## Releases

Each release contains a complete, directly flashable `boot.img` for one stock
software version, plus the kernel `Image` it was built from and a `SHA256SUMS`
file. The stock kernel payload is identical across the three versions, so the
same audited kernel is repacked against each version's own stock boot template.

| HyperOS version | Target | Status |
| --- | --- | --- |
| `4.0.0.26.XPCCNXM` | Android 17 / Xiaomi 17 / `pudding` | device-tested on `boot_a`, 2026-09-15 |
| `4.0.0.16.XPCCNXM` | Android 17 / Xiaomi 17 / `pudding` | device-tested on `boot_b`, 2026-09-03 |
| `4.0.0.9.XPCCNXM` | Android 17 / Xiaomi 17 / `pudding` | static audit; the 2026-08-27 device-tested binaries were not retained |

Pick the release that matches the HyperOS version already installed on your
device. The boot image is a complete boot-format image for the plain `boot`
partition; do not write the raw `Image` to a partition.

## What this project does

The active `r30-stock-containers` variant enables:

~~~text
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_DEVTMPFS=y
CONFIG_USER_NS=y
~~~

It preserves stock GKI/module compatibility by keeping the patch delta small,
isolating the SYSVIPC layout from Rust bindgen, updating the ABI snapshot, and
auditing both vendor modules and stock `system_dlkm` consumers.

## Current validation status

- 973 stock modules audited: 466 vendor ramdisk modules + 103 `system_dlkm`
  modules + 404 `vendor_dlkm` modules.
- The current audit runs against the module trees unpacked from the HyperOS
  `4.0.0.26.XPCCNXM` OTA package; 53,527 module imports were checked with zero
  missing, CRC-mismatch, provider-conflict, or present-unexported results.
- `rust_binder.ko` imports audited separately; all 234 imports matched.
- A Xiaomi 17 `pudding` device booted the User Namespace candidate on HyperOS
  `4.0.0.16` and again on `4.0.0.26`, and passed the `unshare -Ur` runtime
  smoke test.
- The modified boot image does not have a valid Xiaomi AVB signature. Treat any
  generated boot image as a device-specific research artifact, not as a general
  installation package.

## Repository layout

~~~text
docs/                         Detailed Chinese engineering archive
kernel-work/source-locks/     Pinned Android Common and Droidspaces inputs
kernel-work/variants/         Public patches, scripts, and variant notes
~~~

Build outputs, logs, caches, upstream checkouts, stock images, and device
backups are ignored by Git. See [`kernel-work/README.md`](kernel-work/README.md)
for the workflow and [`docs/VALIDATION.md`](docs/VALIDATION.md) for the concise
public validation summary.

## Version profile on this branch

This branch targets the Xiaomi 17 `pudding` (`25113PN0EC`) stock software profile:
Android 17, Settings version `4.0.0.26.XPCCNXM.D00`, and stock kernel release
`6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k`. The stock kernel payload is
byte-identical across HyperOS `4.0.0.9`, `4.0.0.16`, and `4.0.0.26`, so the same
audited Image is repacked against each version's own stock boot template. The
`.26` candidate has been written to the device's active `boot_a` and booted
successfully; see
[`docs/PLATFORM_PROFILE.md`](docs/PLATFORM_PROFILE.md) for the exact values and the
migration boundary, and
[`docs/RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.26.md`](docs/RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.26.md)
for the current adaptation record.

## Important safety boundary

Do not flash a generated image unless you understand the bootloader, AVB,
rollback, partition, and recovery implications for your exact device. Never
publish or exchange `persist`, `fsg`, `modemst*`, calibration, NV, or other
device-unique partitions. Keep a verified stock backup outside this repository.

## Search terms

`Droidspaces` · `Xiaomi 17` · `25113PN0EC` · `pudding` · `SM8850` · `canoe`
· HyperOS `4.0.0.26.XPCCNXM` · HyperOS `4.0.0.16.XPCCNXM` · HyperOS
`4.0.0.9.XPCCNXM` · `OS4.0.0.26.XPCCNXM` · `CP2A.260605.016` · Android 17 · SDK 37
· Android GKI 6.12 · `android16-6.12-2026-03_r30` · Linux kernel · custom kernel
· `boot.img` · boot image · repack · User Namespace · `CONFIG_USER_NS` · PID
namespace · `CONFIG_PID_NS` · IPC namespace · `CONFIG_IPC_NS` · SYSV IPC ·
`CONFIG_SYSVIPC` · POSIX mqueue · devtmpfs · `unshare` · container · Docker ·
Flatpak · Bubblewrap · sandbox · KernelSU · Rust Binder · KMI · CRC · module
vermagic · Kleaf · Bazel · 小米 17 · 澎湃 OS · 内核 · 容器 · 用户命名空间

## License and upstream notices

The patch files include their upstream provenance where applicable. Android
Common Kernel and Droidspaces components remain subject to their respective
upstream licenses. No additional project-wide license is asserted here until
the provenance of every original and derived file has been reviewed.
