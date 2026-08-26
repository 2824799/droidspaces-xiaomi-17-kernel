#!/usr/bin/env python3
"""Audit stock Android vendor modules against a candidate kernel build.

The script uses only ELF data embedded in the modules and the candidate
Module.symvers. It understands both classic __versions entries and Android's
extended modversion sections.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import json
import pathlib
import struct
import subprocess
from typing import Iterable


@dataclasses.dataclass(frozen=True)
class Section:
    name: str
    offset: int
    size: int
    link: int
    entsize: int


@dataclasses.dataclass
class ModuleInfo:
    path: pathlib.Path
    name: str
    vermagic: str
    imports: dict[str, int]
    exports: dict[str, int]


class Elf64LE:
    def __init__(self, path: pathlib.Path):
        self.path = path
        self.data = path.read_bytes()
        if self.data[:4] != b"\x7fELF" or self.data[4] != 2 or self.data[5] != 1:
            raise ValueError(f"unsupported ELF: {path}")
        shoff = struct.unpack_from("<Q", self.data, 40)[0]
        shentsize, shnum, shstrndx = struct.unpack_from("<HHH", self.data, 58)
        raw = []
        for index in range(shnum):
            values = struct.unpack_from("<IIQQQQIIQQ", self.data, shoff + index * shentsize)
            raw.append(values)
        shstr = raw[shstrndx]
        shstr_data = self.data[shstr[4] : shstr[4] + shstr[5]]
        self.sections: list[Section] = []
        for values in raw:
            name_off, _, _, _, offset, size, link, _, _, entsize = values
            end = shstr_data.find(b"\0", name_off)
            name = shstr_data[name_off:end].decode(errors="replace") if name_off else ""
            self.sections.append(Section(name, offset, size, link, entsize))
        self.by_name = {section.name: section for section in self.sections}

    def section_data(self, name: str) -> bytes | None:
        section = self.by_name.get(name)
        if section is None:
            return None
        return self.data[section.offset : section.offset + section.size]

    def symbols(self) -> Iterable[tuple[str, int, int]]:
        symtab_index = next(
            (i for i, section in enumerate(self.sections) if section.name == ".symtab"), None
        )
        if symtab_index is None:
            return []
        symtab = self.sections[symtab_index]
        strtab = self.sections[symtab.link]
        strings = self.data[strtab.offset : strtab.offset + strtab.size]
        result = []
        entsize = symtab.entsize or 24
        for offset in range(symtab.offset, symtab.offset + symtab.size, entsize):
            name_off, _, _, shndx, value, _ = struct.unpack_from("<IBBHQQ", self.data, offset)
            end = strings.find(b"\0", name_off)
            name = strings[name_off:end].decode(errors="replace") if name_off else ""
            result.append((name, shndx, value))
        return result


def split_nul_strings(data: bytes) -> list[str]:
    return [item.decode(errors="replace") for item in data.split(b"\0") if item]


def parse_imports(elf: Elf64LE) -> dict[str, int]:
    names_data = elf.section_data("__version_ext_names")
    crcs_data = elf.section_data("__version_ext_crcs")
    if names_data is not None and crcs_data is not None:
        names = split_nul_strings(names_data)
        crcs = list(struct.unpack(f"<{len(crcs_data) // 4}I", crcs_data))
        if len(names) != len(crcs):
            raise ValueError(f"extended modversion count mismatch: {elf.path}")
        return dict(zip(names, crcs))

    versions = elf.section_data("__versions")
    if versions is None:
        return {}
    result: dict[str, int] = {}
    if len(versions) % 64:
        raise ValueError(f"unexpected __versions size: {elf.path}")
    for offset in range(0, len(versions), 64):
        crc = struct.unpack_from("<Q", versions, offset)[0] & 0xFFFFFFFF
        raw_name = versions[offset + 8 : offset + 64].split(b"\0", 1)[0]
        if raw_name:
            result[raw_name.decode(errors="replace")] = crc
    return result


def parse_exports(elf: Elf64LE) -> dict[str, int]:
    result: dict[str, int] = {}
    for name, shndx, value in elf.symbols():
        if not name.startswith("__crc_") or shndx == 0 or shndx >= len(elf.sections):
            continue
        section = elf.sections[shndx]
        if not section.name.startswith("__kcrctab"):
            continue
        file_offset = section.offset + value
        if file_offset + 4 <= len(elf.data):
            result[name[len("__crc_") :]] = struct.unpack_from("<I", elf.data, file_offset)[0]
    return result


def parse_modinfo(elf: Elf64LE) -> dict[str, str]:
    data = elf.section_data(".modinfo") or b""
    result: dict[str, str] = {}
    for item in split_nul_strings(data):
        if "=" in item:
            key, value = item.split("=", 1)
            result.setdefault(key, value)
    return result


def parse_module(path: pathlib.Path) -> ModuleInfo:
    elf = Elf64LE(path)
    modinfo = parse_modinfo(elf)
    return ModuleInfo(
        path=path,
        name=modinfo.get("name", path.stem),
        vermagic=modinfo.get("vermagic", ""),
        imports=parse_imports(elf),
        exports=parse_exports(elf),
    )


def parse_symvers(path: pathlib.Path) -> dict[str, list[tuple[int, str]]]:
    providers: dict[str, list[tuple[int, str]]] = collections.defaultdict(list)
    for line in path.read_text(errors="replace").splitlines():
        fields = line.split()
        if len(fields) < 3:
            continue
        providers[fields[1]].append((int(fields[0], 16), fields[2]))
    return providers


def load_vmlinux_symbols(path: pathlib.Path | None) -> set[str]:
    if path is None:
        return set()
    output = subprocess.check_output(["nm", "-a", str(path)], text=True, errors="replace")
    result = set()
    for line in output.splitlines():
        fields = line.split()
        if fields:
            result.add(fields[-1])
    return result


def vermagic_suffix(value: str) -> str:
    return value.split(" ", 1)[1] if " " in value else value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--modules-dir", required=True, type=pathlib.Path)
    parser.add_argument("--module-symvers", required=True, type=pathlib.Path)
    parser.add_argument("--reference-module", required=True, type=pathlib.Path)
    parser.add_argument(
        "--provider-modules-dir", action="append", default=[], type=pathlib.Path
    )
    parser.add_argument("--vmlinux", type=pathlib.Path)
    parser.add_argument("--report-dir", required=True, type=pathlib.Path)
    args = parser.parse_args()

    args.report_dir.mkdir(parents=True, exist_ok=True)
    paths = sorted(args.modules_dir.rglob("*.ko"))
    modules = [parse_module(path) for path in paths]
    reference = parse_module(args.reference_module)
    all_candidate_providers = parse_symvers(args.module_symvers)
    # A boot-only test deploys the candidate vmlinux but retains the stock
    # vendor/system_dlkm modules. Candidate-built .ko providers therefore must
    # not override the providers that will actually be loaded on the device.
    candidate_providers = {
        symbol: [(crc, provider) for crc, provider in providers if provider == "vmlinux"]
        for symbol, providers in all_candidate_providers.items()
    }
    candidate_providers = {symbol: providers for symbol, providers in candidate_providers.items() if providers}

    # Vendor-ramdisk modules load before system_dlkm. If both trees contain the
    # same module name (for example zsmalloc), keep the vendor-ramdisk copy.
    provider_by_name: dict[str, ModuleInfo] = {module.name: module for module in modules}
    for directory in args.provider_modules_dir:
        for path in directory.rglob("*.ko"):
            module = parse_module(path)
            provider_by_name.setdefault(module.name, module)
    provider_modules = list(provider_by_name.values())

    vendor_providers: dict[str, list[tuple[int, str]]] = collections.defaultdict(list)
    for module in provider_modules:
        for symbol, crc in module.exports.items():
            vendor_providers[symbol].append((crc, module.name))

    vmlinux_symbols = load_vmlinux_symbols(args.vmlinux)
    issues = []
    status_counts: collections.Counter[str] = collections.Counter()
    modules_with_issues: set[str] = set()
    import_count = 0
    for module in modules:
        for symbol, expected_crc in sorted(module.imports.items()):
            import_count += 1
            kernel_options = candidate_providers.get(symbol, [])
            vendor_options = vendor_providers.get(symbol, [])
            options = kernel_options or vendor_options
            if not options:
                status = "present_unexported" if symbol in vmlinux_symbols else "missing"
                selected_crc = None
                selected_provider = ""
            else:
                selected_crc, selected_provider = options[0]
                unique = {crc for crc, _ in kernel_options + vendor_options}
                if len(unique) > 1:
                    status = "provider_conflict"
                elif selected_crc != expected_crc:
                    status = "crc_mismatch"
                else:
                    status = "ok"
            status_counts[status] += 1
            if status != "ok":
                modules_with_issues.add(module.name)
                issues.append(
                    {
                        "module": module.name,
                        "file": str(module.path),
                        "symbol": symbol,
                        "status": status,
                        "expected_crc": f"0x{expected_crc:08x}",
                        "selected_crc": "" if selected_crc is None else f"0x{selected_crc:08x}",
                        "selected_provider": selected_provider,
                        "kernel_providers": kernel_options,
                        "vendor_providers": vendor_options,
                    }
                )

    release_mismatch = [
        module.name
        for module in modules
        if module.vermagic and reference.vermagic and module.vermagic.split(" ", 1)[0] != reference.vermagic.split(" ", 1)[0]
    ]
    flag_mismatch = [
        module.name
        for module in modules
        if module.vermagic and reference.vermagic and vermagic_suffix(module.vermagic) != vermagic_suffix(reference.vermagic)
    ]

    summary = {
        "modules": len(modules),
        "imports": import_count,
        "vendor_exports": sum(len(module.exports) for module in modules),
        "candidate_vmlinux_symbols": len(candidate_providers),
        "provider_modules": len(provider_modules),
        "reference_vermagic": reference.vermagic,
        "status_counts": dict(sorted(status_counts.items())),
        "modules_with_issues": len(modules_with_issues),
        "release_mismatch_modules": len(release_mismatch),
        "flag_mismatch_modules": len(flag_mismatch),
        "audit_pass": not issues and not flag_mismatch,
    }

    (args.report_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    with (args.report_dir / "issues.tsv").open("w") as stream:
        stream.write("module\tsymbol\tstatus\texpected_crc\tselected_crc\tselected_provider\n")
        for issue in issues:
            stream.write(
                "\t".join(
                    str(issue[key])
                    for key in ("module", "symbol", "status", "expected_crc", "selected_crc", "selected_provider")
                )
                + "\n"
            )
    (args.report_dir / "issues.json").write_text(json.dumps(issues, indent=2, sort_keys=True) + "\n")
    (args.report_dir / "release-mismatch-modules.txt").write_text("\n".join(sorted(release_mismatch)) + "\n")
    (args.report_dir / "flag-mismatch-modules.txt").write_text("\n".join(sorted(flag_mismatch)) + "\n")

    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["audit_pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
