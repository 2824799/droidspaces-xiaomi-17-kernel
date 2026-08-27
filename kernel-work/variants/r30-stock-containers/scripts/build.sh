#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/nahida/agents/tmp/kernel-work"
VARIANT="r30-stock-containers"
WORKTREE="$ROOT/worktrees/$VARIANT"
OUT_ROOT="$ROOT/out/$VARIANT"
LOG_ROOT="$ROOT/logs/$VARIANT"
ARTIFACT_ROOT="$ROOT/artifacts/$VARIANT"
META_DIR="$ROOT/variants/$VARIANT/metadata"
TARGET="//common:kernel_aarch64_abi_dist"
JOBS="${JOBS:-16}"
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
LOG_DIR="$LOG_ROOT/$BUILD_ID"
ARTIFACT_DIR="$ARTIFACT_ROOT/$BUILD_ID"
BAZEL_ROOT="$OUT_ROOT/bazel-user-root"
REPO_MANIFEST="$ROOT/source-locks/r30/checked-out-manifest.xml"
BAZEL_ROOT="${BAZEL_ROOT_OVERRIDE:-$BAZEL_ROOT}"

[[ -x "$WORKTREE/tools/bazel" ]] || {
  echo "Missing worktree; run create-worktree.sh first" >&2
  exit 1
}
[[ -f "$REPO_MANIFEST" ]] || {
  echo "Missing pinned repo manifest: $REPO_MANIFEST" >&2
  exit 1
}
mkdir -p "$OUT_ROOT" "$LOG_DIR" "$ARTIFACT_DIR" "$META_DIR"

COMMON_ARGS=(
  --output_user_root="$BAZEL_ROOT"
  --stdout_stderr_regex_allowlist="$WORKTREE/build/kernel/kleaf/spotless_log_regex.txt"
)
BUILD_ARGS=(
  --repo_manifest="$WORKTREE:$REPO_MANIFEST"
  --jobs="$JOBS"
  --keep_going
  --make_jobs="$JOBS"
  --make_keep_going
  --config=android_ci
  --config=silent
)

{
  printf 'build_id=%s\n' "$BUILD_ID"
  printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'variant=%s\n' "$VARIANT"
  printf 'target=%s\n' "$TARGET"
  printf 'jobs=%s\n' "$JOBS"
  printf 'worktree=%s\n' "$WORKTREE"
  printf 'output_user_root=%s\n' "$BAZEL_ROOT"
  printf 'repo_manifest=%s\n' "$REPO_MANIFEST"
  printf 'artifact_dir=%s\n' "$ARTIFACT_DIR"
  printf 'host=%s\n' "$(uname -a)"
} | tee "$LOG_DIR/build-metadata.txt" > "$META_DIR/last-build.txt"

cd "$WORKTREE"
KLEAF_USE_KLEAF_LOCALVERSION=true \
KLEAF_REPO_MANIFEST="$WORKTREE:$REPO_MANIFEST" \
  build/kernel/kleaf/workspace_status.sh > "$LOG_DIR/workspace-status.txt"
grep -Eq '^STABLE_SCMVERSIONS .*"common": "-[^"]+"' \
  "$LOG_DIR/workspace-status.txt" || {
    echo "Kleaf workspace status did not resolve common SCMVERSION" >&2
    cat "$LOG_DIR/workspace-status.txt" >&2
    exit 1
  }
printf '%q ' tools/bazel "${COMMON_ARGS[@]}" build "${BUILD_ARGS[@]}" "$TARGET" > "$LOG_DIR/build-command.txt"
printf '\n' >> "$LOG_DIR/build-command.txt"

echo "[1/2] Building $TARGET"
tools/bazel "${COMMON_ARGS[@]}" build "${BUILD_ARGS[@]}" "$TARGET" 2>&1 | tee "$LOG_DIR/build.log"

printf '%q ' tools/bazel "${COMMON_ARGS[@]}" run "${BUILD_ARGS[@]}" "$TARGET" -- --destdir="$ARTIFACT_DIR" --quiet > "$LOG_DIR/dist-command.txt"
printf '\n' >> "$LOG_DIR/dist-command.txt"

echo "[2/2] Exporting dist artifacts"
tools/bazel "${COMMON_ARGS[@]}" run "${BUILD_ARGS[@]}" "$TARGET" -- --destdir="$ARTIFACT_DIR" --quiet 2>&1 | tee "$LOG_DIR/dist.log"

# Keep the raw dist names and add the conventional names expected by kernel
# tooling and human inspection.
if [[ -f "$ARTIFACT_DIR/kernel_aarch64_dot_config" ]]; then
  cp -a "$ARTIFACT_DIR/kernel_aarch64_dot_config" "$ARTIFACT_DIR/.config"
fi
if [[ -f "$ARTIFACT_DIR/kernel_aarch64_Module.symvers" ]]; then
  cp -a "$ARTIFACT_DIR/kernel_aarch64_Module.symvers" "$ARTIFACT_DIR/Module.symvers"
fi

printf 'finished_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$LOG_DIR/build-metadata.txt" >> "$META_DIR/last-build.txt"
ln -sfn "$BUILD_ID" "$ARTIFACT_ROOT/latest"
ln -sfn "$BUILD_ID" "$LOG_ROOT/latest"
echo "Artifacts exported to $ARTIFACT_DIR"
