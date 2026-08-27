#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/nahida/agents/tmp/kernel-work"
VARIANT="r30-stock-compat"
UPSTREAM="$ROOT/upstream/android16-6.12-2026-03-r30"
WORKTREE="$ROOT/worktrees/$VARIANT"
REPO="$ROOT/tools/repo"
ARTIFACT_DIR="${1:-$ROOT/artifacts/$VARIANT/latest}"
META_DIR="$ROOT/variants/$VARIANT/metadata"
STOCK_MODULE_CERT="$WORKTREE/common/certs/stock_system_dlkm_signing_key.pem"
EXPECTED_STOCK_MODULE_CERT_SERIAL="4B2A816CD76DB5930B2A44680C9BAC6639C63607"

[[ -d "$ARTIFACT_DIR" ]] || { echo "Artifact directory not found: $ARTIFACT_DIR" >&2; exit 1; }
ARTIFACT_DIR=$(readlink -f "$ARTIFACT_DIR")
REPORT="$ARTIFACT_DIR/verification.txt"
[[ -f "$ARTIFACT_DIR/Image" ]] || { echo "Image is missing from $ARTIFACT_DIR" >&2; exit 1; }
[[ -f "$STOCK_MODULE_CERT" ]] || { echo "Stock module certificate is missing: $STOCK_MODULE_CERT" >&2; exit 1; }
mkdir -p "$META_DIR"
cert_der=$(mktemp)
trap 'rm -f "$cert_der"' EXIT
openssl x509 -in "$STOCK_MODULE_CERT" -outform DER -out "$cert_der"
stock_cert_serial=$(openssl x509 -in "$STOCK_MODULE_CERT" -noout -serial | sed 's/^serial=//')
stock_cert_sha=$(sha256sum "$cert_der" | awk '{print $1}')
[[ "$stock_cert_serial" == "$EXPECTED_STOCK_MODULE_CERT_SERIAL" ]] || {
  echo "Unexpected stock module certificate serial: $stock_cert_serial" >&2
  exit 1
}
grep -qx 'CONFIG_SYSTEM_TRUSTED_KEYS="certs/stock_system_dlkm_signing_key.pem"' "$ARTIFACT_DIR/.config" || {
  echo "Kernel config does not embed the stock module signing certificate" >&2
  exit 1
}
python3 - "$ARTIFACT_DIR/vmlinux" "$cert_der" <<'PY'
import pathlib
import sys
vmlinux = pathlib.Path(sys.argv[1]).read_bytes()
certificate = pathlib.Path(sys.argv[2]).read_bytes()
if certificate not in vmlinux:
    raise SystemExit("stock module signing certificate is absent from vmlinux")
PY

{
  printf 'verified_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'artifact_dir=%s\n\n' "$ARTIFACT_DIR"
  echo '[Image]'
  file "$ARTIFACT_DIR/Image"
  stat -c 'size=%s bytes' "$ARTIFACT_DIR/Image"
  strings "$ARTIFACT_DIR/Image" | grep -m1 '^Linux version ' || true
  echo
  echo '[vmlinux]'
  if [[ -f "$ARTIFACT_DIR/vmlinux" ]]; then
    file "$ARTIFACT_DIR/vmlinux"
    stat -c 'size=%s bytes' "$ARTIFACT_DIR/vmlinux"
  else
    echo 'missing'
  fi
  echo
  echo '[stock system_dlkm module certificate]'
  printf 'trusted=yes\nserial=%s\nsha256=%s\n' "$stock_cert_serial" "$stock_cert_sha"
  openssl x509 -in "$STOCK_MODULE_CERT" -noout -subject -issuer -dates -fingerprint -sha1
  echo
  echo '[SHA256]'
  find "$ARTIFACT_DIR" -maxdepth 1 -type f ! -name SHA256SUMS ! -name verification.txt -printf '%f\0' | sort -z | xargs -0 -r -I{} sha256sum "$ARTIFACT_DIR/{}"
  echo
  echo '[upstream status]'
  (cd "$UPSTREAM" && "$REPO" status)
  echo
  echo '[worktree changes]'
  while IFS= read -r path; do
    status=$(git -C "$WORKTREE/$path" status --porcelain)
    [[ -z "$status" ]] || printf '%s\n%s\n' "$path" "$status"
  done < <(cd "$UPSTREAM" && "$REPO" list -p)
  echo
  echo '[common patch history]'
  git -C "$WORKTREE/common" log -4 --format='%H %s'
} | tee "$REPORT"

(cd "$ARTIFACT_DIR" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 -r sha256sum > SHA256SUMS)

image_sha=$(sha256sum "$ARTIFACT_DIR/Image" | awk '{print $1}')
vmlinux_sha=$(sha256sum "$ARTIFACT_DIR/vmlinux" | awk '{print $1}')
config_sha=$(sha256sum "$ARTIFACT_DIR/.config" | awk '{print $1}')
symvers_sha=$(sha256sum "$ARTIFACT_DIR/Module.symvers" | awk '{print $1}')
vmlinux_symvers_sha=$(sha256sum "$ARTIFACT_DIR/vmlinux.symvers" | awk '{print $1}')
kernel_release=$(strings "$ARTIFACT_DIR/Image" | sed -n 's/^Linux version \([^ ]*\).*/\1/p' | head -n1)
{
  printf 'variant=%s\n' "$VARIANT"
  printf 'verified_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'base_tag=android16-6.12-2026-03_r30\n'
  printf 'base_common_commit=6c9833506661b564ae3bedd6378ff80a3718e256\n'
  printf 'patched_common_head=%s\n' "$(git -C "$WORKTREE/common" rev-parse HEAD)"
  printf 'kernel_release=%s\n' "$kernel_release"
  printf 'image_size=%s\n' "$(stat -c %s "$ARTIFACT_DIR/Image")"
  printf 'image_sha256=%s\n' "$image_sha"
  printf 'vmlinux_size=%s\n' "$(stat -c %s "$ARTIFACT_DIR/vmlinux")"
  printf 'vmlinux_sha256=%s\n' "$vmlinux_sha"
  printf 'config_sha256=%s\n' "$config_sha"
  printf 'module_symvers_sha256=%s\n' "$symvers_sha"
  printf 'vmlinux_symvers_sha256=%s\n' "$vmlinux_symvers_sha"
  printf 'stock_module_signing_cert_trusted=yes\n'
  printf 'stock_module_signing_cert_serial=%s\n' "$stock_cert_serial"
  printf 'stock_module_signing_cert_sha256=%s\n' "$stock_cert_sha"
  printf 'artifact_dir=%s\n' "$ARTIFACT_DIR"
  printf 'verification=%s\n' "$REPORT"
  printf 'sha256sums=%s\n' "$ARTIFACT_DIR/SHA256SUMS"
} | tee "$META_DIR/build-result.txt"

echo "Verification report: $REPORT"
