# Droidspaces Xiaomi 17 Kernel Work

Reproducible kernel patches and validation notes for enabling Android container
primitives on the Xiaomi 17 (`pudding`, Qualcomm SM8850 / `canoe`) with the
Android Common Kernel `android16-6.12-2026-03_r30` GKI baseline.

This repository is intentionally a source-and-process project. It contains the
patch series, source locks, build/audit scripts, and public validation notes. It
does not contain Android source checkouts, stock firmware, device backups,
private keys, or generated kernel images.

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

- 569 stock modules audited: 466 vendor modules + 103 `system_dlkm` modules.
- 28,290 module imports checked with zero missing, CRC-mismatch, provider-conflict,
  or present-unexported results in the final audit.
- `rust_binder.ko` imports audited separately; all 234 imports matched.
- A Xiaomi 17 `pudding` device booted the User Namespace candidate and passed the
  `unshare -Ur` runtime smoke test.
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

## Important safety boundary

Do not flash a generated image unless you understand the bootloader, AVB,
rollback, partition, and recovery implications for your exact device. Never
publish or exchange `persist`, `fsg`, `modemst*`, calibration, NV, or other
device-unique partitions. Keep a verified stock backup outside this repository.

## Search terms

`Droidspaces` · `Xiaomi 17` · `pudding` · `SM8850` · `canoe` · Android GKI
6.12 · Linux kernel · User Namespace · PID namespace · IPC namespace · SYSV IPC
· POSIX mqueue · devtmpfs · KernelSU · Rust Binder · KMI · CRC · Kleaf · Bazel

## License and upstream notices

The patch files include their upstream provenance where applicable. Android
Common Kernel and Droidspaces components remain subject to their respective
upstream licenses. No additional project-wide license is asserted here until
the provenance of every original and derived file has been reviewed.
