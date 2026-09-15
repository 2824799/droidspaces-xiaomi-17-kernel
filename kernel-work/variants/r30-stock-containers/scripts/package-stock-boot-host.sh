#!/usr/bin/env bash
# Assemble a complete Android header-v4 boot image on the host, without an
# attached device.
#
# This is the portable counterpart of package-stock-boot.sh.  The device script
# runs the ARM64 MagiskBoot binary on the phone and cross-checks the result;
# this script uses repack-stock-boot.py, whose output was proven byte-for-byte
# identical to the device MagiskBoot repack for the archived stock template.
#
# Required:
#   STOCK_BOOT          verified stock boot image used as the template
#   STOCK_BOOT_SHA256   expected SHA-256 of that template
# Optional:
#   IMAGE               kernel Image (default: artifacts/$VARIANT/latest/Image)
#   ARTIFACT_DIR        output directory (default: artifacts/$VARIANT-host/$BUILD_ID)
#   BOOT_NAME           output file name (default: boot-$VARIANT.img)
#   RELEASE_LABEL       free-text target description recorded in the metadata
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
PROJECT_ROOT="$(cd -- "$ROOT/.." && pwd)"
relative_path() { realpath --relative-to="$PROJECT_ROOT" "$1"; }
VARIANT="r30-stock-containers"

STOCK_BOOT="${STOCK_BOOT:?Set STOCK_BOOT to a verified stock boot image}"
STOCK_BOOT_SHA256="${STOCK_BOOT_SHA256:?Set STOCK_BOOT_SHA256 to its expected SHA-256}"
IMAGE="${IMAGE:-$ROOT/artifacts/$VARIANT/latest/Image}"
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT/artifacts/$VARIANT-host/$BUILD_ID}"
BOOT_NAME="${BOOT_NAME:-boot-$VARIANT.img}"
RELEASE_LABEL="${RELEASE_LABEL:-unspecified}"
AUDIT_META="${AUDIT_META:-$ROOT/variants/$VARIANT/metadata/module-audit-result.txt}"
REPACK="$ROOT/variants/$VARIANT/scripts/repack-stock-boot.py"
VERIFY="$ROOT/variants/$VARIANT/scripts/verify-stock-boot.py"
EXPECTED_STOCK_KERNEL_SHA256="${EXPECTED_STOCK_KERNEL_SHA256:-574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2}"
EXPECTED_STOCK_SIZE="${EXPECTED_STOCK_SIZE:-100663296}"

meta_value() {
  local key="$1" file="$2"
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

for input in "$STOCK_BOOT" "$IMAGE" "$REPACK" "$VERIFY" "$AUDIT_META"; do
  [[ -f "$input" ]] || { echo "Missing input: $input" >&2; exit 1; }
done
[[ ! -e "$ARTIFACT_DIR" ]] || { echo "Artifact already exists: $ARTIFACT_DIR" >&2; exit 1; }

# Module audit gates, identical to the device packaging script.
[[ "$(meta_value variant "$AUDIT_META")" == "$VARIANT" ]] || { echo "Audit metadata variant mismatch" >&2; exit 1; }
[[ "$(meta_value audit_pass "$AUDIT_META")" == yes ]] || { echo "Module audit has not passed" >&2; exit 1; }
[[ "$(meta_value vendor_modules "$AUDIT_META")" == 466 ]] || { echo "Vendor audit did not cover 466 modules" >&2; exit 1; }
[[ "$(meta_value system_dlkm_modules "$AUDIT_META")" == 103 ]] || { echo "system_dlkm audit did not cover 103 modules" >&2; exit 1; }
[[ "$(meta_value vendor_dlkm_modules "$AUDIT_META")" == 404 ]] || { echo "vendor_dlkm audit did not cover 404 modules" >&2; exit 1; }
[[ "$(meta_value total_modules "$AUDIT_META")" == 973 ]] || { echo "Combined audit did not cover 973 modules" >&2; exit 1; }
[[ "$(meta_value rust_binder_bad_imports "$AUDIT_META")" == 0 ]] || { echo "rust_binder has incompatible imports" >&2; exit 1; }
[[ "$(meta_value rust_binder_audit_pass "$AUDIT_META")" == yes ]] || { echo "rust_binder audit did not pass" >&2; exit 1; }
for prefix in vendor system_dlkm vendor_dlkm; do
  for key in missing crc_mismatch provider_conflict present_unexported flag_mismatch_modules; do
    [[ "$(meta_value "${prefix}_$key" "$AUDIT_META")" == 0 ]] || { echo "Module audit gate failed: ${prefix}_$key" >&2; exit 1; }
  done
done

EXPECTED_IMAGE_SHA256="$(meta_value image_sha256 "$AUDIT_META")"
AUDIT_REPORT_DIR="$(meta_value report_dir "$AUDIT_META")"
[[ "$AUDIT_REPORT_DIR" = /* ]] || AUDIT_REPORT_DIR="$PROJECT_ROOT/$AUDIT_REPORT_DIR"
[[ -n "$EXPECTED_IMAGE_SHA256" ]] || { echo "Missing image_sha256 in audit metadata" >&2; exit 1; }

for pair in "$STOCK_BOOT:$STOCK_BOOT_SHA256:stock boot template" "$IMAGE:$EXPECTED_IMAGE_SHA256:kernel Image"; do
  file="${pair%%:*}"; rest="${pair#*:}"; expected="${rest%%:*}"; label="${rest#*:}"
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || { echo "$label hash mismatch: $actual" >&2; exit 1; }
  [[ "$(stat -c %s "$file")" -gt 0 ]] || { echo "$label is empty" >&2; exit 1; }
done
[[ "$(stat -c %s "$STOCK_BOOT")" == "$EXPECTED_STOCK_SIZE" ]] || { echo "Unexpected stock boot size" >&2; exit 1; }

mkdir -p "$ARTIFACT_DIR/review/module-audit"

"$REPACK" "$STOCK_BOOT" "$IMAGE" "$ARTIFACT_DIR/$BOOT_NAME" | tee "$ARTIFACT_DIR/repack.txt"
cp "$IMAGE" "$ARTIFACT_DIR/Image"

set +e
"$VERIFY" \
  "$ARTIFACT_DIR/$BOOT_NAME" "$STOCK_BOOT" "$ARTIFACT_DIR/Image" \
  --expected-stock-boot-sha256 "$STOCK_BOOT_SHA256" \
  --expected-stock-kernel-sha256 "$EXPECTED_STOCK_KERNEL_SHA256" \
  | tee "$ARTIFACT_DIR/verification.txt"
verify_exit=${PIPESTATUS[0]}
set -e
[[ "$verify_exit" == 0 ]] || { echo "Structural verification failed" >&2; exit 1; }

cp "$AUDIT_META" "$ARTIFACT_DIR/review/module-audit-result.txt"
if [[ -d "$AUDIT_REPORT_DIR" ]]; then
  cp -a "$AUDIT_REPORT_DIR/." "$ARTIFACT_DIR/review/module-audit/"
fi

cat > "$ARTIFACT_DIR/REVIEW-STATUS.txt" <<EOF_REVIEW
variant=$VARIANT
release_label=$RELEASE_LABEL
stock_boot_sha256=$STOCK_BOOT_SHA256
stock_boot_size=$EXPECTED_STOCK_SIZE
stock_kernel_sha256=$EXPECTED_STOCK_KERNEL_SHA256
candidate_kernel_sha256=$EXPECTED_IMAGE_SHA256
repack_engine=host-python
repack_equivalent_to_device_magiskboot=proven_for_archived_stock_template
device_boot_test=not_run
xiaomi_avb_signature_valid=no
flash_allowed=no
EOF_REVIEW

{
  printf 'build_id=%s\n' "$BUILD_ID"
  printf 'built_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'variant=%s\n' "$VARIANT"
  printf 'release_label=%s\n' "$RELEASE_LABEL"
  printf 'stock_boot=%s\n' "$(relative_path "$STOCK_BOOT")"
  printf 'stock_boot_sha256=%s\n' "$STOCK_BOOT_SHA256"
  printf 'stock_kernel_sha256=%s\n' "$EXPECTED_STOCK_KERNEL_SHA256"
  printf 'input_image=%s\n' "$(relative_path "$IMAGE")"
  printf 'input_image_sha256=%s\n' "$EXPECTED_IMAGE_SHA256"
  printf 'module_audit_report=%s\n' "$(relative_path "$AUDIT_META")"
  printf 'candidate=%s\n' "$(relative_path "$ARTIFACT_DIR/$BOOT_NAME")"
  printf 'candidate_sha256=%s\n' "$(sha256sum "$ARTIFACT_DIR/$BOOT_NAME" | awk '{print $1}')"
  printf 'xiaomi_avb_signature_valid=no\n'
  printf 'device_boot_test=not_run\n'
} | tee "$ARTIFACT_DIR/build-result.txt"

(cd "$ARTIFACT_DIR" && find . -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 -r sha256sum > SHA256SUMS)
(cd "$ARTIFACT_DIR" && sha256sum -c SHA256SUMS)
echo "Boot candidate: $ARTIFACT_DIR/$BOOT_NAME"
