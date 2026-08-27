#!/usr/bin/env python3
"""Repack a header-v4 stock boot image with a raw replacement kernel.

This implements the exact layout used by MagiskBoot for the Xiaomi stock
template used by this variant: preserve the 4 KiB header page and stock vbmeta
blob, replace the raw kernel, move vbmeta after the page-aligned kernel, and
update the AVB footer offsets.  The caller is expected to prove byte-for-byte
equivalence against a known MagiskBoot repack before using the result.
"""

from __future__ import annotations

import argparse
import pathlib
import struct

PAGE_SIZE = 4096
FOOTER_SIZE = 64


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("stock_boot", type=pathlib.Path)
    parser.add_argument("kernel", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    stock = args.stock_boot.read_bytes()
    kernel = args.kernel.read_bytes()

    if stock[:8] != b"ANDROID!":
        raise ValueError("stock template is not an Android boot image")
    if len(stock) < PAGE_SIZE + FOOTER_SIZE or stock[-64:-60] != b"AVBf":
        raise ValueError("stock template has no AVB footer")

    stock_kernel_size, stock_ramdisk_size, _, header_size = struct.unpack_from(
        "<IIII", stock, 8
    )
    header_version = struct.unpack_from("<I", stock, 40)[0]
    if header_version != 4 or header_size != 1584 or stock_ramdisk_size != 0:
        raise ValueError(
            "expected header v4, header_size 1584, and an empty ramdisk"
        )
    if stock_kernel_size <= 0 or len(kernel) <= 0:
        raise ValueError("kernel size must be non-zero")

    magic, major, minor, _, vbmeta_offset, vbmeta_size, reserved = struct.unpack(
        ">4sIIQQQ28s", stock[-FOOTER_SIZE:]
    )
    if vbmeta_offset + vbmeta_size > len(stock) - FOOTER_SIZE:
        raise ValueError("stock vbmeta range is outside the image")
    vbmeta = stock[vbmeta_offset : vbmeta_offset + vbmeta_size]
    if not vbmeta.startswith(b"AVB0"):
        raise ValueError("stock vbmeta blob has no AVB0 header")

    header_page = bytearray(stock[:PAGE_SIZE])
    struct.pack_into("<I", header_page, 8, len(kernel))

    output = bytearray(header_page)
    output.extend(kernel)
    output.extend(bytes(align_up(len(output), PAGE_SIZE) - len(output)))
    new_vbmeta_offset = len(output)
    output.extend(vbmeta)

    payload_limit = len(stock) - FOOTER_SIZE
    if len(output) > payload_limit:
        raise ValueError("replacement kernel and vbmeta do not fit the image")
    output.extend(bytes(payload_limit - len(output)))

    # For a boot partition with an appended hash footer, original_image_size
    # excludes the vbmeta blob.  This matches the archived MagiskBoot output.
    output.extend(
        struct.pack(
            ">4sIIQQQ28s",
            magic,
            major,
            minor,
            new_vbmeta_offset,
            new_vbmeta_offset,
            vbmeta_size,
            reserved,
        )
    )

    if len(output) != len(stock):
        raise AssertionError("repacked image size changed unexpectedly")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
