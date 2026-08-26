#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/nahida/agents/tmp/kernel-work"
VARIANT="r30-control"
UPSTREAM="$ROOT/upstream/android16-6.12-2026-03-r30"
WORKTREE="$ROOT/worktrees/$VARIANT"
REPO="$ROOT/tools/repo"
ARTIFACT_DIR="${1:-$ROOT/artifacts/$VARIANT/latest}"

[[ -d "$ARTIFACT_DIR" ]] || { echo "Artifact directory not found: $ARTIFACT_DIR" >&2; exit 1; }
ARTIFACT_DIR=$(readlink -f "$ARTIFACT_DIR")
REPORT="$ARTIFACT_DIR/verification.txt"
[[ -f "$ARTIFACT_DIR/Image" ]] || { echo "Image is missing from $ARTIFACT_DIR" >&2; exit 1; }

{
  printf 'verified_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'artifact_dir=%s\n\n' "$(readlink -f "$ARTIFACT_DIR")"
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
} | tee "$REPORT"

(cd "$ARTIFACT_DIR" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 -r sha256sum > SHA256SUMS)
echo "Verification report: $REPORT"
