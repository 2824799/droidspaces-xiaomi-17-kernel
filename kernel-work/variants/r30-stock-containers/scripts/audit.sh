#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/nahida/agents/tmp/kernel-work"
VARIANT="r30-stock-containers"
ARTIFACT_DIR="${1:-$ROOT/artifacts/$VARIANT/latest}"
BASELINE="$ROOT/cache/device-baseline/pudding-stock-20260826"
MODULES_DIR="$BASELINE/vendor_ramdisk/lib/modules"
PROVIDER_DIR="$BASELINE/system_dlkm_flatten"
AUDIT_ID="${AUDIT_ID:-$(date -u +%Y%m%dT%H%M%SZ)-stock466}"
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
[[ -d "$MODULES_DIR" ]] || { echo "Missing stock modules: $MODULES_DIR" >&2; exit 1; }
[[ -d "$PROVIDER_DIR" ]] || { echo "Missing provider modules: $PROVIDER_DIR" >&2; exit 1; }
mkdir -p "$REPORT_DIR" "$(dirname "$META")"

{
  printf 'audit_id=%s\n' "$AUDIT_ID"
  printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'artifact_dir=%s\n' "$ARTIFACT_DIR"
  printf 'image_sha256=%s\n' "$(sha256sum "$ARTIFACT_DIR/Image" | awk '{print $1}')"
  printf 'vmlinux_sha256=%s\n' "$(sha256sum "$ARTIFACT_DIR/vmlinux" | awk '{print $1}')"
  printf 'module_symvers_sha256=%s\n' "$(sha256sum "$ARTIFACT_DIR/Module.symvers" | awk '{print $1}')"
  printf 'modules_dir=%s\n' "$MODULES_DIR"
  printf 'provider_modules_dir=%s\n' "$PROVIDER_DIR"
  printf 'vendor_ramdisk_module_count=%s\n' "$(find "$MODULES_DIR" -type f -name '*.ko' | wc -l)"
} > "$REPORT_DIR/audit-context.txt"

grep -E '__tracepoint_android_vh_(cma_alloc_lat_(start|end)|dma_heap_buffer_alloc_lat_(start|end)|mm_direct_reclaim_(start|end))([[:space:]]|$)' \
  "$ARTIFACT_DIR/Module.symvers" | sort > "$REPORT_DIR/required-hooks.txt"

set +e
"$AUDITOR" \
  --modules-dir "$MODULES_DIR" \
  --provider-modules-dir "$PROVIDER_DIR" \
  --module-symvers "$ARTIFACT_DIR/Module.symvers" \
  --reference-module "$ARTIFACT_DIR/r8152.ko" \
  --vmlinux "$ARTIFACT_DIR/vmlinux" \
  --report-dir "$REPORT_DIR" 2>&1 | tee "$REPORT_DIR/console.txt"
audit_exit=${PIPESTATUS[0]}
set -e

python3 - "$REPORT_DIR/summary.json" "$REPORT_DIR/audit-context.txt" "$META" "$REPORT_DIR" "$audit_exit" <<'PY'
import hashlib
import json
import pathlib
import sys

summary_path = pathlib.Path(sys.argv[1])
context_path = pathlib.Path(sys.argv[2])
meta_path = pathlib.Path(sys.argv[3])
report_dir = pathlib.Path(sys.argv[4]).resolve()
audit_exit = int(sys.argv[5])
summary = json.loads(summary_path.read_text())
context = dict(
    line.split("=", 1)
    for line in context_path.read_text().splitlines()
    if "=" in line
)
counts = summary.get("status_counts", {})
required = {
    "missing": int(counts.get("missing", 0)),
    "crc_mismatch": int(counts.get("crc_mismatch", 0)),
    "provider_conflict": int(counts.get("provider_conflict", 0)),
    "present_unexported": int(counts.get("present_unexported", 0)),
}
passed = (
    audit_exit == 0
    and summary.get("audit_pass") is True
    and summary.get("modules") == 466
    and not any(required.values())
    and summary.get("flag_mismatch_modules", 0) == 0
)
lines = [
    "variant=r30-stock-containers",
    f"audit_id={context['audit_id']}",
    f"audit_pass={'yes' if passed else 'no'}",
    f"audit_exit={audit_exit}",
    f"modules={summary.get('modules', 0)}",
    f"imports={summary.get('imports', 0)}",
    f"ok={counts.get('ok', 0)}",
    *(f"{key}={value}" for key, value in required.items()),
    f"modules_with_issues={summary.get('modules_with_issues', 0)}",
    f"release_mismatch_modules={summary.get('release_mismatch_modules', 0)}",
    f"flag_mismatch_modules={summary.get('flag_mismatch_modules', 0)}",
    f"reference_vermagic={summary.get('reference_vermagic', '')}",
    f"image_sha256={context['image_sha256']}",
    f"vmlinux_sha256={context['vmlinux_sha256']}",
    f"module_symvers_sha256={context['module_symvers_sha256']}",
    f"report_dir={report_dir}",
    f"summary_sha256={hashlib.sha256(summary_path.read_bytes()).hexdigest()}",
]
meta_path.write_text("\n".join(lines) + "\n")
print(meta_path.read_text(), end="")
raise SystemExit(0 if passed else 2)
PY

ln -sfn "$AUDIT_ID" "$REPORT_ROOT/latest"
echo "Module audit report: $REPORT_DIR"
