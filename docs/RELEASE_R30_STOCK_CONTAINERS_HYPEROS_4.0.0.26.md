# R30 stock-containers / HyperOS 4.0.0.26 adaptation record

This record covers the `r30-stock-containers` kernel adapted to the Xiaomi 17
`pudding` full OTA package named
`pudding-ota_full-OS4.0.0.26.XPCCNXM-user-17.0-9c0a5c052e.zip`.

The stock kernel payload in that OTA is byte-for-byte identical to the payload
already covered by the `4.0.0.9` and `4.0.0.16` records, so no kernel rebuild was
required. The candidate for this version is a repack of the existing audited
Image against the `.26` stock boot template, followed by a full module audit
against the `.26` module trees. Device verification has not been performed yet.

## Version identity

```text
OEM package:        pudding-ota_full-OS4.0.0.26.XPCCNXM-user-17.0-9c0a5c052e.zip
Device:             Xiaomi 17, model 25113PN0EC, codename pudding
Platform:           Qualcomm SM8850 / canoe
Android:            17, SDK 37
Settings version:   4.0.0.26.XPCCNXM.D00
Build ID:           CP2A.260605.016
Security patch:     2026-08-01
POST-build label:   17OS4.0.260905.065436767.QCPECN.S
Kernel release:     6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k
```

The OTA's own metadata records the installed build as
`Xiaomi/pudding/pudding:17/CP2A.260605.016/17OS4.0.260905.065436767.QCPECN.S:user/release-keys`.
The boot and vendor components of that package were built with the older label
`OS4.0.0.25.XPCCN`, while the product, `mi_ext`, and `mi_product` partitions
carry `OS4.0.0.26.XPCCNXM`.

## Why no rebuild was needed

The stock boot image extracted from the `.26` package and the stock boot image
pulled from the device on the `.16` branch contain the same kernel payload:

```text
stock kernel payload size: 41507328 bytes
stock kernel payload SHA-256 (identical in .9, .16, and .26):
574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2
```

The `.26` and `.16` stock boot images differ only in the AVB metadata that
carries the version label: 543 bytes of the 100663296-byte image, all inside the
vbmeta blob after the kernel. Every module import that the candidate kernel has
to satisfy was therefore audited against the `.26` module trees rather than
against a rebuilt kernel.

## Module change between the previous baseline and `.26`

The `.26` module trees were unpacked from the OTA package: 466 vendor modules
from the vendor ramdisk inside `vendor_boot`, and 103 modules from the
`system_dlkm` partition.

```text
vendor ramdisk modules: 466, none added or removed, 415 byte-identical, 51 changed
system_dlkm modules:    103, all 103 byte-identical
```

The 51 changed vendor modules still resolve every import against the candidate
kernel; the audit result for the complete set is recorded below.

## Audit result for `.26`

```text
vendor ramdisk modules / imports:  466 / 22504
system_dlkm modules / imports:     103 / 5816
vendor_dlkm modules / imports:     404 / 25207
total modules / imports:           973 / 53527
stock rust_binder imports:         234, all matched
missing / CRC mismatch / provider conflict / present-unexported:  0 / 0 / 0 / 0
legacy module flag mismatch:       0
strict ABI/KMI:                    pass
audit verdict:                     pass
```

This audit also extends the consumer coverage of the earlier records. The `.9`
and `.16` releases audited 466 vendor ramdisk modules plus 103 `system_dlkm`
modules. The `vendor_dlkm` partition is separate and shares only 295 modules with
the vendor ramdisk, so 109 `*_dlkm.ko` modules - audio, camera, display, and the
rest of the vendor DLKM set - had never been checked against the candidate
kernel. All of them now resolve every import too, which is the same class of gap
that previously hid the `rust_binder` KMI regression.

The reference vermagic is
`6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k SMP preempt mod_unload modversions aarch64`,
matching the candidate kernel and the stock module set.

One consistent value is worth recording so it is not mistaken for a new finding:
the 466 vendor ramdisk modules and the 404 `vendor_dlkm` modules report a
vermagic string that differs from the candidate's trailing
`SMP preempt mod_unload modversions aarch64`, exactly as in the earlier `.9`
audit, and that field is not an acceptance gate.

## Candidate asset identity

```text
Kernel Image size:    42232320 bytes
Kernel Image SHA-256: 9645dec7d368198597372c64fcb45b9bd525238a42e7e8c8098911a2e4040aae
Boot image size:      100663296 bytes
Boot image SHA-256:   b974c356caf877d3c30893a117b83a2c69955f14ed088ead98641bd32207ba19
Stock template:       100663296 bytes, SHA-256
                      b752ce64344608ad325fdf67804e0ff15c023b7b7c7a12d4a859d576354959b1
Boot format:          Android header version 4, 4096-byte pages, no ramdisk
```

The repack touches only the kernel region and the `kernel_size` field of the
header page, reuses the stock vbmeta blob unchanged, and keeps the image size
identical to the stock partition image. Structural verification passes: the size
equals the stock template, the header version is 4, the ramdisk size is 0, the
embedded kernel matches the audited Image, the template kernel matches the
archived stock payload, and the stock vbmeta blob is reused.

## Host repack equivalence

The repack used for this version runs on the host through
`kernel-work/variants/r30-stock-containers/scripts/repack-stock-boot.py`. Its
output was already proven byte-for-byte identical to the ARM64 MagiskBoot repack
performed on the device for the archived stock template: feeding that template
and the audited Image into the host script reproduces the exact 100663296-byte
image whose SHA-256 is
`6066cebcbb1d1e6d0ec48db48ee5f45ea0c0aef14fedcd0ed279f12e6df2f633`, which was
written to the device on the `.16` branch and read back unchanged. Both templates
use the same header version, page size, header size, empty ramdisk, and vbmeta
size, so the same layout code path applies.

## Validation status

```text
static module audit:       pass, against the .26 module trees
structural verification:   pass
bootloader/AVB signature:  not valid; the kernel payload is unsigned
device boot test:          not run for this candidate
```

This candidate has not been started on hardware. The `.16` boot image carrying
the same kernel Image was device-tested on September 3, 2026; see
[`RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.16.md`](RELEASE_R30_STOCK_CONTAINERS_HYPEROS_4.0.0.16.md).
Until the `.26` candidate is flashed and observed, treat it as an audited build
with an unverified runtime state.

## OTA extraction procedure

The boot template and module trees for this version were produced from the OTA
package with the repository's own tooling, without an attached device:

```sh
# boot partition image used as the repack template
kernel-work/variants/r30-stock-containers/scripts/extract-payload-partition.py \
  pudding-ota_full-OS4.0.0.26.XPCCNXM-user-17.0-9c0a5c052e.zip boot \
  kernel-work/cache/ota-4.0.0.26/boot.img

# system_dlkm tree (EROFS image, extracted with erofs-utils)
fsck.erofs --extract=kernel-work/cache/ota-4.0.0.26/extract/system_dlkm \
  kernel-work/cache/ota-4.0.0.26/system_dlkm.img

# vendor_boot: LZ4-decompress the vendor ramdisk, then unpack the cpio archive
# kernel-work/cache/ota-4.0.0.26/vendor_ramdisk.cpio
```

The partition extractor verifies every reconstructed image against the SHA-256
recorded in the payload manifest and reports a mismatch instead of writing a
partial file.

## Use conditions

- Target only Xiaomi 17 `pudding` hardware running this Android 17 / HyperOS
  `4.0.0.26.XPCCNXM` software, or another build whose stock boot template is
  byte-identical to the one recorded above.
- Keep a verified stock backup of the matching boot partition before writing
  anything, and keep it outside this repository.
- The published boot image is a complete boot-format image, but the modified
  kernel payload is not signed by Xiaomi's production AVB key. A successful boot
  on one device does not prove compatibility with another region, build, or
  bootloader policy.
- Do not modify `vbmeta`, `vendor_boot`, `init_boot`, calibration partitions,
  modem/NV partitions, or other device-unique partitions based on this record.
