#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/nahida/agents/tmp/kernel-work"
VARIANT="r30-stock-compat"
STOCK_BOOT="${STOCK_BOOT:-/home/nahida/agents/tmp/backup/字库备份_1787746457069/boot_a.img}"
IMAGE="${IMAGE:-$ROOT/artifacts/$VARIANT/latest/Image}"
REPACK_SCRIPT="$ROOT/variants/$VARIANT/scripts/repack-stock-boot.py"
VERIFY_SCRIPT="$ROOT/variants/$VARIANT/scripts/verify-stock-boot.py"
BUILD_META="$ROOT/variants/$VARIANT/metadata/build-result.txt"
AUDIT_META="$ROOT/variants/$VARIANT/metadata/module-audit-result.txt"
PATCH_PROVENANCE="$ROOT/variants/$VARIANT/metadata/patch-provenance.txt"
PATCH_HASHES="$ROOT/variants/$VARIANT/metadata/patch-sha256.txt"
REFERENCE_IMAGE="$ROOT/artifacts/r30-control-stock-template/latest/Image"
REFERENCE_BOOT="$ROOT/artifacts/r30-control-stock-template/latest/boot-r30-control-stock-template.img"
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="$ROOT/out/$VARIANT/package-stock-boot-local/$BUILD_ID"
ARTIFACT_ROOT="$ROOT/artifacts/r30-stock-compat-stock-template"
ARTIFACT_DIR="$ARTIFACT_ROOT/$BUILD_ID"
META="$ROOT/variants/$VARIANT/metadata/stock-template-build-result.txt"
EXPECTED_STOCK_BOOT_SHA256="af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b"
EXPECTED_REFERENCE_IMAGE_SHA256="9888b71a440c6713f820fe4e1775f460bb9ae6272444bdeaba5039357ae59a24"
EXPECTED_REFERENCE_BOOT_SHA256="b66b1d547142fcedea03b9d1b270a41b19eb7dd53b36dad1fba5d5413b7eb6e6"

meta_value() {
  local key="$1" file="$2"
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

for input in "$STOCK_BOOT" "$IMAGE" "$REPACK_SCRIPT" "$VERIFY_SCRIPT" \
  "$BUILD_META" "$AUDIT_META" "$PATCH_PROVENANCE" "$PATCH_HASHES" \
  "$REFERENCE_IMAGE" "$REFERENCE_BOOT"; do
  [[ -f "$input" ]] || { echo "Missing input: $input" >&2; exit 1; }
done

EXPECTED_IMAGE_SHA256=$(meta_value image_sha256 "$BUILD_META")
AUDIT_IMAGE_SHA256=$(meta_value image_sha256 "$AUDIT_META")
AUDIT_REPORT_DIR=$(meta_value report_dir "$AUDIT_META")
[[ -n "$EXPECTED_IMAGE_SHA256" ]] || { echo "Missing image_sha256 in build metadata" >&2; exit 1; }
[[ "$(meta_value variant "$BUILD_META")" == "$VARIANT" ]] || { echo "Build metadata variant mismatch" >&2; exit 1; }
[[ "$(meta_value audit_pass "$AUDIT_META")" == yes ]] || { echo "Module audit has not passed" >&2; exit 1; }
[[ "$(meta_value modules "$AUDIT_META")" == 466 ]] || { echo "Module audit did not cover 466 modules" >&2; exit 1; }
for key in missing crc_mismatch provider_conflict present_unexported flag_mismatch_modules; do
  [[ "$(meta_value "$key" "$AUDIT_META")" == 0 ]] || { echo "Module audit gate failed: $key" >&2; exit 1; }
done
[[ "$AUDIT_IMAGE_SHA256" == "$EXPECTED_IMAGE_SHA256" ]] || { echo "Audit/build Image hash mismatch" >&2; exit 1; }
[[ -d "$AUDIT_REPORT_DIR" && -f "$AUDIT_REPORT_DIR/summary.json" ]] || { echo "Missing module audit report" >&2; exit 1; }
[[ "$(sha256sum "$AUDIT_REPORT_DIR/summary.json" | awk '{print $1}')" == "$(meta_value summary_sha256 "$AUDIT_META")" ]] || {
  echo "Module audit summary hash mismatch" >&2; exit 1;
}
[[ "$(sha256sum "$STOCK_BOOT" | awk '{print $1}')" == "$EXPECTED_STOCK_BOOT_SHA256" ]] || {
  echo "Stock boot hash mismatch" >&2; exit 1;
}
[[ "$(sha256sum "$IMAGE" | awk '{print $1}')" == "$EXPECTED_IMAGE_SHA256" ]] || {
  echo "Candidate Image hash mismatch" >&2; exit 1;
}
[[ "$(sha256sum "$REFERENCE_IMAGE" | awk '{print $1}')" == "$EXPECTED_REFERENCE_IMAGE_SHA256" ]] || {
  echo "Reference Image hash mismatch" >&2; exit 1;
}
[[ "$(sha256sum "$REFERENCE_BOOT" | awk '{print $1}')" == "$EXPECTED_REFERENCE_BOOT_SHA256" ]] || {
  echo "Reference MagiskBoot repack hash mismatch" >&2; exit 1;
}
[[ ! -e "$ARTIFACT_DIR" ]] || { echo "Artifact already exists: $ARTIFACT_DIR" >&2; exit 1; }

mkdir -p "$OUT_DIR" "$ARTIFACT_DIR/review/module-audit"
REFERENCE_REPACK="$OUT_DIR/reference-repacked-locally.img"
CANDIDATE="$ARTIFACT_DIR/boot-r30-stock-compat-stock-template.img"

python3 "$REPACK_SCRIPT" "$STOCK_BOOT" "$REFERENCE_IMAGE" "$REFERENCE_REPACK"
{
  sha256sum "$REFERENCE_IMAGE" "$REFERENCE_REPACK" "$REFERENCE_BOOT"
  if cmp -s "$REFERENCE_REPACK" "$REFERENCE_BOOT"; then
    echo "reference_repack_byte_identical=yes"
  else
    echo "reference_repack_byte_identical=no"
    exit 1
  fi
} | tee "$OUT_DIR/repack-equivalence.txt"

python3 "$REPACK_SCRIPT" "$STOCK_BOOT" "$IMAGE" "$CANDIDATE"
"$VERIFY_SCRIPT" "$CANDIDATE" "$STOCK_BOOT" "$IMAGE" | tee "$ARTIFACT_DIR/verification.txt"

cp "$IMAGE" "$ARTIFACT_DIR/Image"
cp "$OUT_DIR/repack-equivalence.txt" "$ARTIFACT_DIR/"
cp "$BUILD_META" "$ARTIFACT_DIR/review/kernel-build-result.txt"
cp "$AUDIT_META" "$ARTIFACT_DIR/review/module-audit-result.txt"
cp "$PATCH_PROVENANCE" "$PATCH_HASHES" "$ARTIFACT_DIR/review/"
cp -a "$AUDIT_REPORT_DIR/." "$ARTIFACT_DIR/review/module-audit/"

cat > "$ARTIFACT_DIR/DO-NOT-FLASH.txt" <<'NOTICE'
DO NOT FLASH THIS IMAGE TO boot_a, boot_b, init_boot, OR ANY OTHER PARTITION.
This modified Xiaomi stock-template boot image is for temporary fastboot boot testing only.
Replacing the kernel invalidates the Xiaomi AVB cryptographic signature.
NOTICE

cat > "$ARTIFACT_DIR/REVIEW-STATUS.txt" <<EOF_REVIEW
variant=$VARIANT
base=android16-6.12-2026-03_r30 plus four official R31 Xiaomi compatibility commits
vendor_module_audit_pass=yes
vendor_modules_audited=466
imports_checked=22474
missing=0
crc_mismatch=0
provider_conflict=0
present_unexported=0
release_mismatch_modules=0
flag_mismatch_modules=0
stock_template_size_bytes=100663296
boot_header_version=4
boot_ramdisk_size=0
candidate_kernel_sha256=$EXPECTED_IMAGE_SHA256
pack_method=local deterministic header-v4 repack
pack_method_magiskboot_reference_byte_identical=yes
kernelsu_pairing_pass=no
kernelsu_note=not covered; exact KernelSU LKM or a no-KernelSU init_boot is still required before a clean device test
device_boot_test=not_run
xiaomi_avb_signature_valid=no
allowed_use=fastboot_boot_only
flash_allowed=no
EOF_REVIEW

candidate_sha=$(sha256sum "$CANDIDATE" | awk '{print $1}')
{
  printf 'build_id=%s\n' "$BUILD_ID"
  printf 'built_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'variant=%s\n' "$VARIANT"
  printf 'stock_boot=%s\n' "$STOCK_BOOT"
  printf 'stock_boot_sha256=%s\n' "$EXPECTED_STOCK_BOOT_SHA256"
  printf 'input_image=%s\n' "$IMAGE"
  printf 'input_image_sha256=%s\n' "$EXPECTED_IMAGE_SHA256"
  printf 'module_audit_pass=yes\n'
  printf 'module_audit_report=%s\n' "$AUDIT_REPORT_DIR"
  printf 'pack_method=local-deterministic-header-v4\n'
  printf 'reference_magiskboot_repack=%s\n' "$REFERENCE_BOOT"
  printf 'reference_magiskboot_repack_sha256=%s\n' "$EXPECTED_REFERENCE_BOOT_SHA256"
  printf 'reference_repack_byte_identical=yes\n'
  printf 'candidate=%s\n' "$CANDIDATE"
  printf 'candidate_size=100663296\n'
  printf 'candidate_sha256=%s\n' "$candidate_sha"
  printf 'xiaomi_avb_signature_valid=no\n'
  printf 'allowed_use=fastboot_boot_only\n'
  printf 'flash_allowed=no\n'
} | tee "$ARTIFACT_DIR/build-result.txt" > "$META"

(cd "$ARTIFACT_DIR" && find . -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 -r sha256sum > SHA256SUMS)
(cd "$ARTIFACT_DIR" && sha256sum -c SHA256SUMS)
ln -sfn "$BUILD_ID" "$ARTIFACT_ROOT/latest"
echo "Stock-template candidate: $CANDIDATE"
