#!/usr/bin/env python3
"""Verify an R30 boot candidate repacked from the Xiaomi stock boot image."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import struct

PAGE_SIZE = 4096
EXPECTED_STOCK_SIZE = 100663296
EXPECTED_STOCK_BOOT_SHA256 = (
    "af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b"
)
EXPECTED_STOCK_KERNEL_SHA256 = (
    "574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def marker_offsets(data: bytes, marker: bytes) -> list[int]:
    result: list[int] = []
    offset = 0
    while True:
        offset = data.find(marker, offset)
        if offset < 0:
            return result
        result.append(offset)
        offset += 1


def parse_boot(path: pathlib.Path) -> tuple[bytes, dict[str, object]]:
    data = path.read_bytes()
    if data[:8] != b"ANDROID!":
        raise ValueError(f"not an Android boot image: {path}")

    kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from(
        "<IIII", data, 8
    )
    header_version = struct.unpack_from("<I", data, 40)[0]
    signature_size = (
        struct.unpack_from("<I", data, 1580)[0]
        if header_version >= 4 and len(data) >= 1584
        else 0
    )
    kernel_offset = ((header_size + PAGE_SIZE - 1) // PAGE_SIZE) * PAGE_SIZE
    kernel = data[kernel_offset : kernel_offset + kernel_size]

    footer = None
    if data[-64:-60] == b"AVBf":
        _, major, minor, original_size, vbmeta_offset, vbmeta_size, _ = struct.unpack(
            ">4sIIQQQ28s", data[-64:]
        )
        footer = {
            "major": major,
            "minor": minor,
            "original_image_size": original_size,
            "vbmeta_offset": vbmeta_offset,
            "vbmeta_size": vbmeta_size,
            "vbmeta_sha256": sha256(
                data[vbmeta_offset : vbmeta_offset + vbmeta_size]
            ),
        }

    info: dict[str, object] = {
        "size": len(data),
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "os_version": os_version,
        "header_size": header_size,
        "header_version": header_version,
        "signature_size": signature_size,
        "kernel_offset": kernel_offset,
        "kernel_sha256": sha256(kernel),
        "android_count": data.count(b"ANDROID!"),
        "avb0_offsets": marker_offsets(data, b"AVB0"),
        "avbf_offsets": marker_offsets(data, b"AVBf"),
        "footer": footer,
    }
    return data, info


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate", type=pathlib.Path)
    parser.add_argument("stock_boot", type=pathlib.Path)
    parser.add_argument("image", type=pathlib.Path)
    args = parser.parse_args()

    candidate_data, candidate = parse_boot(args.candidate)
    stock_data, stock = parse_boot(args.stock_boot)
    image_data = args.image.read_bytes()

    print("[inputs]")
    print(f"candidate={args.candidate}")
    print(f"candidate_sha256={sha256(candidate_data)}")
    print(f"stock_template={args.stock_boot}")
    print(f"stock_template_sha256={sha256(stock_data)}")
    print(f"input_Image={args.image}")
    print(f"input_Image_sha256={sha256(image_data)}")

    print("\n[candidate_header]")
    for key, value in candidate.items():
        print(f"{key}={value}")

    print("\n[stock_header]")
    for key, value in stock.items():
        print(f"{key}={value}")

    candidate_footer = candidate["footer"]
    stock_footer = stock["footer"]
    reused_stock_vbmeta = bool(
        isinstance(candidate_footer, dict)
        and isinstance(stock_footer, dict)
        and candidate_footer["vbmeta_sha256"] == stock_footer["vbmeta_sha256"]
    )

    checks = {
        "candidate_size_equals_stock": candidate["size"]
        == stock["size"]
        == EXPECTED_STOCK_SIZE,
        "header_version_4": candidate["header_version"] == 4,
        "ramdisk_size_0": candidate["ramdisk_size"] == 0,
        "candidate_kernel_matches_input_Image": candidate["kernel_sha256"]
        == sha256(image_data),
        "candidate_kernel_size_matches_input_Image": candidate["kernel_size"]
        == len(image_data),
        "stock_kernel_matches_archived_hash": stock["kernel_sha256"]
        == EXPECTED_STOCK_KERNEL_SHA256,
        "stock_template_hash_matches_archived": sha256(stock_data)
        == EXPECTED_STOCK_BOOT_SHA256,
        "candidate_differs_from_stock": sha256(candidate_data)
        != sha256(stock_data),
        "candidate_has_AVB0": len(candidate["avb0_offsets"]) >= 1,
        "candidate_has_AVBf": len(candidate["avbf_offsets"]) >= 1,
        "candidate_reuses_stock_vbmeta": reused_stock_vbmeta,
    }

    print("\n[acceptance]")
    for key, value in checks.items():
        print(f"{key}={value}")
    print(f"all_structural_checks_pass={all(checks.values())}")

    print("\n[security_boundary]")
    print("modified_payload_has_valid_xiaomi_avb_signature=False")
    print("allowed_use=FASTBOOT_BOOT_ONLY_ON_UNLOCKED_BOOTLOADER")
    print("flash_allowed=False")

    return 0 if all(checks.values()) else 2


if __name__ == "__main__":
    raise SystemExit(main())
