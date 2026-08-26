#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/nahida/agents/tmp/kernel-work"
VARIANT="r30-control"
STOCK_BOOT="${STOCK_BOOT:-/home/nahida/agents/tmp/backup/字库备份_1787746457069/boot_a.img}"
IMAGE="${IMAGE:-$ROOT/artifacts/$VARIANT/latest/Image}"
MAGISKBOOT="${MAGISKBOOT:-$ROOT/tools/magiskboot-arm64}"
VERIFY_SCRIPT="$ROOT/variants/$VARIANT/scripts/verify-stock-boot.py"
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="$ROOT/out/$VARIANT/package-stock-boot/$BUILD_ID"
ARTIFACT_ROOT="$ROOT/artifacts/r30-control-stock-template"
ARTIFACT_DIR="$ARTIFACT_ROOT/$BUILD_ID"
META="$ROOT/variants/$VARIANT/metadata/stock-template-build-result.txt"
DEVICE_DIR="/data/local/tmp/r30-stock-template-$BUILD_ID"
EXPECTED_STOCK_BOOT_SHA256="af83b83f63ae833b05d69b87b8e216c3a0bace798699080e799cd8fff344248b"
EXPECTED_IMAGE_SHA256="9888b71a440c6713f820fe4e1775f460bb9ae6272444bdeaba5039357ae59a24"
EXPECTED_MAGISKBOOT_SHA256="0f2f86d782f7304c28e9e20dc3c3ddfe2e77038c7280ed220002ecb83fa96584"
EXPECTED_STOCK_KERNEL_SHA256="574006dc475adc70dac65ec8cf8fcbbf0b18b0c31584a84702257788964c8ec2"

for input in "$STOCK_BOOT" "$IMAGE" "$MAGISKBOOT" "$VERIFY_SCRIPT"; do
  [[ -f "$input" ]] || { echo "Missing input: $input" >&2; exit 1; }
done
[[ "$(sha256sum "$STOCK_BOOT" | awk '{print $1}')" == "$EXPECTED_STOCK_BOOT_SHA256" ]] || {
  echo "Stock boot hash mismatch" >&2; exit 1;
}
[[ "$(sha256sum "$IMAGE" | awk '{print $1}')" == "$EXPECTED_IMAGE_SHA256" ]] || {
  echo "R30 Image hash mismatch" >&2; exit 1;
}
[[ "$(sha256sum "$MAGISKBOOT" | awk '{print $1}')" == "$EXPECTED_MAGISKBOOT_SHA256" ]] || {
  echo "MagiskBoot hash mismatch" >&2; exit 1;
}
[[ ! -e "$ARTIFACT_DIR" ]] || { echo "Artifact already exists: $ARTIFACT_DIR" >&2; exit 1; }

device_count=$(adb devices | awk '$2 == "device" { count++ } END { print count + 0 }')
[[ "$device_count" == 1 ]] || { echo "Exactly one online ADB device is required" >&2; exit 1; }
[[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == 1 ]] || {
  echo "Device is not fully booted" >&2; exit 1;
}

mkdir -p "$OUT_DIR" "$ARTIFACT_DIR"
cleanup() {
  adb get-state >/dev/null 2>&1 && adb shell "rm -rf '$DEVICE_DIR'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

adb shell "mkdir -p '$DEVICE_DIR/input' '$DEVICE_DIR/tool' '$DEVICE_DIR/pack' '$DEVICE_DIR/output' '$DEVICE_DIR/verify'"
adb push "$MAGISKBOOT" "$DEVICE_DIR/tool/magiskboot" > "$OUT_DIR/push-magiskboot.txt" 2>&1
adb push "$STOCK_BOOT" "$DEVICE_DIR/input/stock-boot-a.img" > "$OUT_DIR/push-stock.txt" 2>&1
adb push "$IMAGE" "$DEVICE_DIR/input/r30-Image" > "$OUT_DIR/push-image.txt" 2>&1
adb shell "chmod 0755 '$DEVICE_DIR/tool/magiskboot'"

adb shell "set -e; cd '$DEVICE_DIR/pack'; ../tool/magiskboot unpack -h ../input/stock-boot-a.img; sha256sum kernel ../input/stock-boot-a.img ../input/r30-Image; ls -la" \
  > "$OUT_DIR/unpack-stock.txt" 2>&1
stock_kernel_sha=$(adb shell "sha256sum '$DEVICE_DIR/pack/kernel'" | awk '{print $1}' | tr -d '\r')
[[ "$stock_kernel_sha" == "$EXPECTED_STOCK_KERNEL_SHA256" ]] || {
  echo "Stock template contains an unexpected kernel" >&2; exit 1;
}

adb shell "set -e; cd '$DEVICE_DIR/pack'; rm -f kernel; cp ../input/r30-Image kernel; sha256sum kernel; ../tool/magiskboot repack ../input/stock-boot-a.img ../output/boot-r30-stock-template.img; stat -c '%n %s' ../output/boot-r30-stock-template.img; sha256sum ../output/boot-r30-stock-template.img" \
  > "$OUT_DIR/repack.txt" 2>&1

adb shell "set -e; cd '$DEVICE_DIR/verify'; ../tool/magiskboot unpack -h ../output/boot-r30-stock-template.img; stat -c '%n %s' kernel ../output/boot-r30-stock-template.img; sha256sum kernel ../output/boot-r30-stock-template.img; echo HEADER; cat header; echo FILES; ls -la" \
  > "$OUT_DIR/verify-device.txt" 2>&1
verified_kernel_sha=$(adb shell "sha256sum '$DEVICE_DIR/verify/kernel'" | awk '{print $1}' | tr -d '\r')
[[ "$verified_kernel_sha" == "$EXPECTED_IMAGE_SHA256" ]] || {
  echo "Repacked candidate does not contain the R30 Image" >&2; exit 1;
}

set +e
adb shell "cd '$DEVICE_DIR/verify'; ../tool/magiskboot verify ../output/boot-r30-stock-template.img" \
  > "$OUT_DIR/magiskboot-verify.txt" 2>&1
magiskboot_verify_exit=$?
set -e
printf '%s\n' "$magiskboot_verify_exit" > "$OUT_DIR/magiskboot-verify.exit"

adb pull "$DEVICE_DIR/output/boot-r30-stock-template.img" \
  "$ARTIFACT_DIR/boot-r30-control-stock-template.img" > "$OUT_DIR/pull-candidate.txt" 2>&1
cp "$IMAGE" "$ARTIFACT_DIR/Image"
cp "$OUT_DIR/unpack-stock.txt" "$OUT_DIR/repack.txt" "$OUT_DIR/verify-device.txt" \
  "$OUT_DIR/magiskboot-verify.txt" "$OUT_DIR/magiskboot-verify.exit" "$ARTIFACT_DIR/"

"$VERIFY_SCRIPT" \
  "$ARTIFACT_DIR/boot-r30-control-stock-template.img" \
  "$STOCK_BOOT" "$ARTIFACT_DIR/Image" | tee "$ARTIFACT_DIR/verification.txt"

cat > "$ARTIFACT_DIR/DO-NOT-FLASH.txt" <<'EOF'
DO NOT FLASH THIS IMAGE TO boot_a, boot_b, init_boot, OR ANY OTHER PARTITION.
This is a modified, stock-template boot image for temporary fastboot boot testing only.
The Xiaomi AVB signature cannot remain cryptographically valid after replacing the kernel.
EOF

candidate_sha=$(sha256sum "$ARTIFACT_DIR/boot-r30-control-stock-template.img" | awk '{print $1}')
{
  printf 'build_id=%s\n' "$BUILD_ID"
  printf 'built_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'stock_boot=%s\n' "$STOCK_BOOT"
  printf 'stock_boot_sha256=%s\n' "$EXPECTED_STOCK_BOOT_SHA256"
  printf 'input_image=%s\n' "$IMAGE"
  printf 'input_image_sha256=%s\n' "$EXPECTED_IMAGE_SHA256"
  printf 'magiskboot=%s\n' "$MAGISKBOOT"
  printf 'magiskboot_sha256=%s\n' "$EXPECTED_MAGISKBOOT_SHA256"
  printf 'candidate=%s\n' "$ARTIFACT_DIR/boot-r30-control-stock-template.img"
  printf 'candidate_size=100663296\n'
  printf 'candidate_sha256=%s\n' "$candidate_sha"
  printf 'magiskboot_verify_exit=%s\n' "$magiskboot_verify_exit"
  printf 'xiaomi_avb_signature_valid=no\n'
  printf 'allowed_use=fastboot_boot_only\n'
  printf 'flash_allowed=no\n'
} | tee "$ARTIFACT_DIR/build-result.txt" > "$META"

(cd "$ARTIFACT_DIR" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 -r sha256sum > SHA256SUMS)
(cd "$ARTIFACT_DIR" && sha256sum -c SHA256SUMS)
ln -sfn "$BUILD_ID" "$ARTIFACT_ROOT/latest"
echo "Stock-template candidate: $ARTIFACT_DIR/boot-r30-control-stock-template.img"
