# Public validation summary

This is the short, public-facing status page. The long-form engineering record
is in [`README.md`](README.md).

## Build and audit

The active variant is `kernel-work/variants/r30-stock-containers/` and is based
on Android Common Kernel `android16-6.12-2026-03_r30`.

The most recent recorded audit covered the module trees unpacked from the
HyperOS `4.0.0.26.XPCCNXM` OTA package:

| Check | Result |
| --- | --- |
| Vendor ramdisk modules | 466 audited |
| Stock `system_dlkm` modules | 103 audited |
| Stock `vendor_dlkm` modules | 404 audited |
| Total modules | 973 |
| Total imports | 53,527 |
| `rust_binder.ko` imports | 234 |
| Missing / CRC mismatch / provider conflict | 0 / 0 / 0 |
| Strict ABI/KMI check | Pass |

The equivalent audit against the previous HyperOS `4.0.0.9`/`4.0.0.16` module
trees covered the vendor ramdisk and `system_dlkm` trees with the same all-green
result. The `vendor_dlkm` consumer tree was added to the audit for `.26`; it
shares only 295 of its modules with the vendor ramdisk, so this closes 109 stock
modules that earlier records did not cover. Between the two baselines all 103
`system_dlkm` modules were byte-identical and 51 of the 466 vendor ramdisk
modules changed.

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
against one device and one stock software baseline, HyperOS `4.0.0.16.XPCCNXM`.
The later `4.0.0.26.XPCCNXM` candidate reuses that identical kernel Image inside
the `.26` stock boot template and has passed the static audit and the structural
boot-image checks, but it has not been started on hardware yet.

## Security boundary

Replacing the kernel payload invalidates the Xiaomi AVB cryptographic signature.
Generated boot images are therefore research artifacts and must not be treated
as signed release images or shared as generic flashing packages. Keep stock
backups and device-unique partitions outside the repository.
