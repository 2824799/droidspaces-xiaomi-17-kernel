#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/nahida/agents/tmp/kernel-work"
VARIANT="r30-stock-containers"
ARTIFACT_DIR="${1:-$ROOT/artifacts/$VARIANT/latest}"
BASELINE="$ROOT/cache/device-baseline/pudding-stock-20260826"
VENDOR_MODULES_DIR="$BASELINE/vendor_ramdisk/lib/modules"
SYSTEM_MODULES_DIR="$BASELINE/system_dlkm_flatten"
AUDIT_ID="${AUDIT_ID:-$(date -u +%Y%m%dT%H%M%SZ)-stock569}"
REPORT_ROOT="$ROOT/logs/$VARIANT/module-audit"
REPORT_DIR="$REPORT_ROOT/$AUDIT_ID"
META="$ROOT/variants/$VARIANT/metadata/module-audit-result.txt"
AUDITOR="$ROOT/variants/$VARIANT/scripts/audit-stock-modules.py"

ARTIFACT_DIR=$(readlink -f "$ARTIFACT_DIR")
for input in \
  "$ARTIFACT_DIR/Image" \
  "$ARTIFACT_DIR/vmlinux" \
  "$ARTIFACT_DIR/Module.symvers" \
  "$ARTIFACT_DIR/r8152.ko" \
  "$AUDITOR"; do
  [[ -f "$input" ]] || { echo "Missing input: $input" >&2; exit 1; }
done
[[ -d "$VENDOR_MODULES_DIR" ]] || { echo "Missing vendor modules: $VENDOR_MODULES_DIR" >&2; exit 1; }
[[ -d "$SYSTEM_MODULES_DIR" ]] || { echo "Missing system_dlkm modules: $SYSTEM_MODULES_DIR" >&2; exit 1; }
mkdir -p "$REPORT_DIR/vendor-ramdisk" "$REPORT_DIR/system-dlkm" "$(dirname "$META")"

vendor_count=$(find "$VENDOR_MODULES_DIR" -type f -name '*.ko' | wc -l)
system_count=$(find "$SYSTEM_MODULES_DIR" -type f -name '*.ko' | wc -l)
{
  printf 'audit_id=%s\n' "$AUDIT_ID"
  printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'artifact_dir=%s\n' "$ARTIFACT_DIR"
  printf 'image_sha256=%s\n' "$(sha256sum "$ARTIFACT_DIR/Image" | awk '{print $1}')"
  printf 'vmlinux_sha256=%s\n' "$(sha256sum "$ARTIFACT_DIR/vmlinux" | awk '{print $1}')"
  printf 'module_symvers_sha256=%s\n' "$(sha256sum "$ARTIFACT_DIR/Module.symvers" | awk '{print $1}')"
  printf 'vendor_modules_dir=%s\n' "$VENDOR_MODULES_DIR"
  printf 'system_dlkm_modules_dir=%s\n' "$SYSTEM_MODULES_DIR"
  printf 'vendor_ramdisk_module_count=%s\n' "$vendor_count"
  printf 'system_dlkm_module_count=%s\n' "$system_count"
} > "$REPORT_DIR/audit-context.txt"

grep -E '__tracepoint_android_vh_(cma_alloc_lat_(start|end)|dma_heap_buffer_alloc_lat_(start|end)|mm_direct_reclaim_(start|end))([[:space:]]|$)' \
  "$ARTIFACT_DIR/Module.symvers" | sort > "$REPORT_DIR/required-hooks.txt"

run_audit() {
  local label=$1
  local modules_dir=$2
  local provider_dir=$3
  local out="$REPORT_DIR/$label"
  local -a command=(
    "$AUDITOR"
    --modules-dir "$modules_dir"
    --provider-modules-dir "$provider_dir"
    --module-symvers "$ARTIFACT_DIR/Module.symvers"
    --reference-module "$ARTIFACT_DIR/r8152.ko"
    --vmlinux "$ARTIFACT_DIR/vmlinux"
    --report-dir "$out"
  )
  set +e
  "${command[@]}" 2>&1 | tee "$out/console.txt"
  local code=${PIPESTATUS[0]}
  set -e
  printf '%s\n' "$code" > "$out/exit-code.txt"
}

# Each consumer tree keeps its own same-name providers first; the other tree
# supplies fallback providers for cross-partition imports.
run_audit vendor-ramdisk "$VENDOR_MODULES_DIR" "$SYSTEM_MODULES_DIR"
run_audit system-dlkm "$SYSTEM_MODULES_DIR" "$VENDOR_MODULES_DIR"

python3 - "$REPORT_DIR" "$REPORT_DIR/audit-context.txt" "$META" <<'PY'
import csv
import hashlib
import json
import pathlib
import sys

report_dir = pathlib.Path(sys.argv[1]).resolve()
context_path = pathlib.Path(sys.argv[2])
meta_path = pathlib.Path(sys.argv[3])
context = dict(
    line.split("=", 1)
    for line in context_path.read_text().splitlines()
    if "=" in line
)

def load(label: str, expected_modules: int):
    directory = report_dir / label
    summary_path = directory / "summary.json"
    summary = json.loads(summary_path.read_text())
    exit_code = int((directory / "exit-code.txt").read_text().strip())
    counts = summary.get("status_counts", {})
    bad = {
        key: int(counts.get(key, 0))
        for key in ("missing", "crc_mismatch", "provider_conflict", "present_unexported")
    }
    passed = (
        exit_code == 0
        and summary.get("audit_pass") is True
        and summary.get("modules") == expected_modules
        and not any(bad.values())
        and summary.get("flag_mismatch_modules", 0) == 0
    )
    return summary, exit_code, bad, passed, summary_path

vendor, vendor_exit, vendor_bad, vendor_pass, vendor_summary_path = load("vendor-ramdisk", 466)
system, system_exit, system_bad, system_pass, system_summary_path = load("system-dlkm", 103)

imports_path = report_dir / "system-dlkm" / "imports.tsv"
with imports_path.open(newline="") as stream:
    rust_rows = [row for row in csv.DictReader(stream, delimiter="\t") if row["module"] == "rust_binder"]
rust_symbols = {row["symbol"] for row in rust_rows}
rust_bad = [row for row in rust_rows if row["status"] != "ok"]
rust_layout_present = "RUST_BINDER_LAYOUT" in rust_symbols
rust_pass = bool(rust_rows) and not rust_bad and rust_layout_present

rust_report = report_dir / "rust-binder-imports.tsv"
with rust_report.open("w", newline="") as stream:
    fieldnames = ["module", "symbol", "status", "expected_crc", "selected_crc", "selected_provider", "file"]
    writer = csv.DictWriter(stream, fieldnames=fieldnames, delimiter="\t")
    writer.writeheader()
    writer.writerows(rust_rows)

passed = vendor_pass and system_pass and rust_pass
total_imports = int(vendor.get("imports", 0)) + int(system.get("imports", 0))
lines = [
    "variant=r30-stock-containers",
    f"audit_id={context['audit_id']}",
    f"audit_pass={'yes' if passed else 'no'}",
    f"vendor_audit_exit={vendor_exit}",
    f"vendor_modules={vendor.get('modules', 0)}",
    f"vendor_imports={vendor.get('imports', 0)}",
    *(f"vendor_{key}={value}" for key, value in vendor_bad.items()),
    f"vendor_release_mismatch_modules={vendor.get('release_mismatch_modules', 0)}",
    f"vendor_flag_mismatch_modules={vendor.get('flag_mismatch_modules', 0)}",
    f"system_dlkm_audit_exit={system_exit}",
    f"system_dlkm_modules={system.get('modules', 0)}",
    f"system_dlkm_imports={system.get('imports', 0)}",
    *(f"system_dlkm_{key}={value}" for key, value in system_bad.items()),
    f"system_dlkm_release_mismatch_modules={system.get('release_mismatch_modules', 0)}",
    f"system_dlkm_flag_mismatch_modules={system.get('flag_mismatch_modules', 0)}",
    f"total_modules={int(vendor.get('modules', 0)) + int(system.get('modules', 0))}",
    f"total_imports={total_imports}",
    f"rust_binder_imports={len(rust_rows)}",
    f"rust_binder_bad_imports={len(rust_bad)}",
    f"rust_binder_layout_symbol_present={'yes' if rust_layout_present else 'no'}",
    f"rust_binder_audit_pass={'yes' if rust_pass else 'no'}",
    f"reference_vermagic={vendor.get('reference_vermagic', '')}",
    f"image_sha256={context['image_sha256']}",
    f"vmlinux_sha256={context['vmlinux_sha256']}",
    f"module_symvers_sha256={context['module_symvers_sha256']}",
    f"report_dir={report_dir}",
    f"vendor_summary_sha256={hashlib.sha256(vendor_summary_path.read_bytes()).hexdigest()}",
    f"system_dlkm_summary_sha256={hashlib.sha256(system_summary_path.read_bytes()).hexdigest()}",
    f"rust_binder_report_sha256={hashlib.sha256(rust_report.read_bytes()).hexdigest()}",
]
meta_path.write_text("\n".join(lines) + "\n")
print(meta_path.read_text(), end="")
raise SystemExit(0 if passed else 2)
PY

ln -sfn "$AUDIT_ID" "$REPORT_ROOT/latest"
echo "Module audit report: $REPORT_DIR"
