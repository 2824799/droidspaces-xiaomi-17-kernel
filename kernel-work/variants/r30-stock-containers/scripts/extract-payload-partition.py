#!/usr/bin/env python3
"""Extract one partition out of an Android OTA payload.bin.

Reads the DeltaArchiveManifest protobuf directly (no protobuf dependency),
applies the install operations for the requested partition, and verifies the
result against the hash recorded in the manifest.
"""

from __future__ import annotations

import argparse
import bz2
import hashlib
import lzma
import pathlib
import struct
import sys
import zipfile

REPLACE = 0
REPLACE_BZ = 1
REPLACE_XZ = 8
ZERO = 6


def read_varint(buf: bytes, pos: int) -> tuple[int, int]:
    shift = 0
    value = 0
    while True:
        byte = buf[pos]
        pos += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, pos
        shift += 7


def iter_fields(buf: bytes, start: int, end: int):
    pos = start
    while pos < end:
        key, pos = read_varint(buf, pos)
        field, wire = key >> 3, key & 0x07
        if wire == 0:
            value, pos = read_varint(buf, pos)
            yield field, wire, value
        elif wire == 2:
            length, pos = read_varint(buf, pos)
            yield field, wire, buf[pos : pos + length]
            pos += length
        elif wire == 5:
            yield field, wire, struct.unpack_from("<I", buf, pos)[0]
            pos += 4
        elif wire == 1:
            yield field, wire, struct.unpack_from("<Q", buf, pos)[0]
            pos += 8
        else:
            raise ValueError(f"unsupported wire type {wire}")


def parse_extent(buf: bytes) -> tuple[int, int]:
    start_block = num_blocks = 0
    for field, _wire, value in iter_fields(buf, 0, len(buf)):
        if field == 1:
            start_block = value
        elif field == 2:
            num_blocks = value
    return start_block, num_blocks


def parse_operation(buf: bytes) -> dict:
    op: dict = {"data_offset": 0, "data_length": 0, "dst": []}
    for field, _wire, value in iter_fields(buf, 0, len(buf)):
        if field == 1:
            op["type"] = value
        elif field == 2:
            op["data_offset"] = value
        elif field == 3:
            op["data_length"] = value
        elif field == 6:
            op["dst"].append(parse_extent(value))
    return op


def parse_partition(buf: bytes) -> dict:
    part: dict = {"operations": [], "size": 0, "hash": b""}
    for field, _wire, value in iter_fields(buf, 0, len(buf)):
        if field == 1:
            part["name"] = value.decode()
        elif field == 7:
            for sub, _sw, sval in iter_fields(value, 0, len(value)):
                if sub == 1:
                    part["size"] = sval
                elif sub == 2:
                    part["hash"] = sval
        elif field == 8:
            part["operations"].append(parse_operation(value))
    return part


def load_manifest(handle) -> tuple[dict, int]:
    # magic (4) + version (8) + manifest size (8) + metadata signature size (4),
    # every numeric field big-endian.  The signature blob itself follows the manifest.
    header = handle.read(24)
    if len(header) != 24:
        raise ValueError(f"short payload header: {len(header)} bytes")
    # The payload header is big-endian; the protobuf manifest that follows is not.
    magic = header[:4]
    version, manifest_size = struct.unpack_from(">QQ", header, 4)
    sig_size = struct.unpack_from(">I", header, 20)[0]
    if magic != b"CrAU" or version != 2:
        raise ValueError("not an update_engine payload v2")
    manifest = handle.read(manifest_size)
    handle.read(sig_size)
    data_start = 20 + manifest_size + 4 + sig_size

    block_size = 4096
    partitions = []
    for field, _wire, value in iter_fields(manifest, 0, len(manifest)):
        if field == 3:
            block_size = value
        elif field == 13:
            partitions.append(parse_partition(value))
    return {"block_size": block_size, "partitions": partitions}, data_start


def apply_operation(handle, data_start: int, block_size: int, op: dict, out: bytearray) -> None:
    total = sum(num_blocks for _start, num_blocks in op["dst"]) * block_size
    handle.seek(data_start + op["data_offset"])
    blob = handle.read(op["data_length"])
    op_type = op["type"]
    if op_type == REPLACE:
        payload = blob
    elif op_type == REPLACE_BZ:
        payload = bz2.decompress(blob)
    elif op_type == REPLACE_XZ:
        payload = lzma.decompress(blob)
    elif op_type == ZERO:
        payload = bytes(total)
    else:
        raise ValueError(f"unsupported install operation type {op_type}")
    if len(payload) != total:
        raise ValueError(f"operation payload size {len(payload)} != {total}")

    cursor = 0
    for start_block, num_blocks in op["dst"]:
        length = num_blocks * block_size
        offset = start_block * block_size
        out[offset : offset + length] = payload[cursor : cursor + length]
        cursor += length


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path, help="payload.bin or OTA zip")
    parser.add_argument("partition", nargs="?")
    parser.add_argument("output", type=pathlib.Path, nargs="?")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    if args.source.suffix == ".zip":
        with zipfile.ZipFile(args.source) as archive:
            info = archive.getinfo("payload.bin")
            if info.compress_type == zipfile.ZIP_STORED:
                # Stored entries are contiguous: read straight out of the archive.
                with args.source.open("rb") as raw:
                    raw.seek(info.header_offset)
                    header = raw.read(30)
                    name_len, extra_len = struct.unpack_from("<HH", header, 26)
                    data_offset = info.header_offset + 30 + name_len + extra_len
                    raw.seek(data_offset)
                    return run(_Sliced(raw, data_offset), args)
            with archive.open("payload.bin") as handle:
                return run(handle, args)
    with args.source.open("rb") as handle:
        return run(handle, args)


def run(handle, args) -> int:
    handle = _Seekable(handle)
    manifest, data_start = load_manifest(handle)
    names = [part["name"] for part in manifest["partitions"]]

    if args.list:
        for part in manifest["partitions"]:
            print(f"{part['name']}\t{part['size']}\t{len(part['operations'])} ops")
        return 0

    if args.partition not in names:
        print(f"partition {args.partition} not present; candidates: {names}", file=sys.stderr)
        return 1
    part = manifest["partitions"][names.index(args.partition)]

    out = bytearray(part["size"])
    for op in part["operations"]:
        apply_operation(handle, data_start, manifest["block_size"], op, out)

    digest = hashlib.sha256(out).hexdigest()
    expected = part["hash"].hex()
    print(f"partition={part['name']} size={len(out)} sha256={digest}")
    print(f"manifest_hash={expected} match={digest == expected}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(out)
    return 0 if digest == expected else 2


class _Seekable:
    """Minimal seek/read wrapper so zipfile streams behave like a file object."""

    def __init__(self, handle) -> None:
        self._handle = handle

    def read(self, size: int = -1) -> bytes:
        return self._handle.read(size)

    def seek(self, offset: int, whence: int = 0) -> int:
        return self._handle.seek(offset, whence)


class _Sliced:
    """Present a region of a file as its own seekable stream."""

    def __init__(self, handle, base: int) -> None:
        self._handle = handle
        self._base = base

    def read(self, size: int = -1) -> bytes:
        return self._handle.read(size)

    def seek(self, offset: int, whence: int = 0) -> int:
        if whence == 0:
            return self._handle.seek(self._base + offset, 0) - self._base
        if whence == 1:
            return self._handle.seek(offset, 1) - self._base
        return self._handle.seek(offset, 2) - self._base


if __name__ == "__main__":
    raise SystemExit(main())
