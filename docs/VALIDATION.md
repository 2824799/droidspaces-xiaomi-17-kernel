# Public validation summary

This is the short, public-facing status page. The long-form engineering record
is in [`README.md`](README.md).

## Build and audit

The active variant is `kernel-work/variants/r30-stock-containers/` and is based
on Android Common Kernel `android16-6.12-2026-03_r30`.

The final recorded audit covered:

| Check | Result |
| --- | --- |
| Vendor modules | 466 audited |
| Stock `system_dlkm` modules | 103 audited |
| Total modules | 569 |
| Total imports | 28,290 |
| `rust_binder.ko` imports | 234 |
| Missing / CRC mismatch / provider conflict | 0 / 0 / 0 |
| Strict ABI/KMI check | Pass |

The public repository keeps the inputs and scripts needed to reproduce these
checks, but not the stock firmware, private device backup, Android checkout,
or generated binaries.

## Device smoke test

On a Xiaomi 17 `pudding` test device, the User Namespace candidate:

- booted to Android;
- loaded the stock module set, including `rust_binder`;
- passed PID namespace, IPC namespace, SYSV IPC, POSIX mqueue, and devtmpfs
  smoke tests;
- passed `unshare -Ur` for User Namespace.

This is not a claim of universal device compatibility. The candidate was tested
against one device and one stock software baseline.

## Security boundary

Replacing the kernel payload invalidates the Xiaomi AVB cryptographic signature.
Generated boot images are therefore research artifacts and must not be treated
as signed release images or shared as generic flashing packages. Keep stock
backups and device-unique partitions outside the repository.
