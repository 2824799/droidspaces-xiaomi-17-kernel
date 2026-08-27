#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/nahida/agents/tmp/kernel-work"
VARIANT="r30-stock-containers"
UPSTREAM="$ROOT/upstream/android16-6.12-2026-03-r30"
WORKTREE="$ROOT/worktrees/$VARIANT"
LOCK_DIR="$ROOT/source-locks/r30"
META_DIR="$ROOT/variants/$VARIANT/metadata"
PATCH_DIR="$ROOT/variants/$VARIANT/patches"
REPO="$ROOT/tools/repo"

if [[ ! -x "$REPO" || ! -d "$UPSTREAM/.repo" ]]; then
  echo "R30 upstream tree is not initialized: $UPSTREAM" >&2
  exit 1
fi

if [[ -e "$WORKTREE" ]]; then
  while IFS= read -r path; do
    [[ -n "$path" && -d "$UPSTREAM/$path" ]] || continue
    git -C "$UPSTREAM/$path" worktree remove --force "$WORKTREE/$path" 2>/dev/null || true
    git -C "$UPSTREAM/$path" worktree prune
  done < <(cd "$UPSTREAM" && "$REPO" list -p)
  rm -rf -- "$WORKTREE"
fi
mkdir -p "$WORKTREE" "$META_DIR"

echo "Creating detached per-project worktrees in $WORKTREE"
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  source_repo="$UPSTREAM/$path"
  target_repo="$WORKTREE/$path"
  sha=$(git -C "$source_repo" rev-parse HEAD)

  if [[ -n $(git -C "$source_repo" status --porcelain) ]]; then
    echo "Refusing to use dirty upstream project: $path" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$target_repo")"
  git -C "$source_repo" worktree add --quiet --detach "$target_repo" "$sha"
done < <(cd "$UPSTREAM" && "$REPO" list -p)

mkdir -p "$WORKTREE/tools"
ln -s ../build/kernel/kleaf/bazel.sh "$WORKTREE/tools/bazel"
ln -s build/kernel/kleaf/bzlmod/bazel.MODULE.bazel "$WORKTREE/MODULE.bazel"
ln -s build/kernel/kleaf/bzlmod/bazel.WORKSPACE.bzlmod "$WORKTREE/WORKSPACE.bzlmod"

# Patches are deliberately external to the source tree. A project may opt in by
# adding patches/<repo path>/series, one patch filename per non-comment line.
while IFS= read -r series; do
  rel=${series#"$PATCH_DIR/"}
  project=${rel%/series}
  [[ -d "$WORKTREE/$project/.git" || -f "$WORKTREE/$project/.git" ]] || {
    echo "Patch series refers to an unknown project: $project" >&2
    exit 1
  }
  while IFS= read -r patch || [[ -n "$patch" ]]; do
    patch=${patch%%#*}
    patch=${patch#"${patch%%[![:space:]]*}"}
    patch=${patch%"${patch##*[![:space:]]}"}
    [[ -n "$patch" ]] || continue
    GIT_COMMITTER_NAME="Codex local builder" \
      GIT_COMMITTER_EMAIL="codex@local.invalid" \
      git -C "$WORKTREE/$project" am --committer-date-is-author-date \
        "$PATCH_DIR/$project/$patch"
  done < "$series"
done < <(find "$PATCH_DIR" -type f -name series -print | sort)

(cd "$UPSTREAM" && "$REPO" manifest -r) > "$LOCK_DIR/checked-out-manifest.xml"
{
  printf 'variant=%s\n' "$VARIANT"
  printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'upstream=%s\n' "$UPSTREAM"
  printf 'worktree=%s\n' "$WORKTREE"
  printf 'patch_series_count=%s\n' "$(find "$PATCH_DIR" -type f -name series | wc -l)"
} > "$META_DIR/worktree.txt"

echo "Worktree ready: $WORKTREE"
