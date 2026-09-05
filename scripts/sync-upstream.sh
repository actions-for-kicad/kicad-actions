#!/usr/bin/env bash
#
# Sync this fork from actions-for-kicad/kicad-actions.
#
# The GLB feature is deliberately built so that it only ever *inserts* lines
# into files upstream also edits -- it modifies no existing upstream line (see
# docs/glb-export.md). That invariant is what makes auto-resolution safe: the
# only conflicts that can arise are two insertions competing for the same
# anchor, and the answer is always "keep both", which is what a union merge
# does.
#
# The invariant is not enforced by git, so this script verifies the merged
# result rather than trusting it, and aborts the merge if anything fails.
#
# Usage:
#   scripts/sync-upstream.sh [--commit] [--upstream URL] [--branch NAME]
#
set -euo pipefail

UPSTREAM_URL="https://github.com/actions-for-kicad/kicad-actions"
UPSTREAM_BRANCH="main"
AUTO_COMMIT=0

# Files where this fork only inserts, so a union merge is always correct.
# Anything conflicting outside this list is a real conflict and stops the run.
UNION_FILES=(action.yml entrypoint.sh)

# Markers proving the GLB feature survived the merge intact. Matched as whole
# lines, so the leading indentation is part of the marker.
declare -A REQUIRED_ONCE=(
  ["entrypoint.sh"]="source /glb/setup.sh|  source /glb/export.sh"
  ["action.yml"]="  pcb_output_glb:"
  ["Dockerfile"]="COPY glb/ /glb/"
)

die() { echo "error: $*" >&2; exit 1; }
note() { echo "==> $*"; }

# Report results to the caller when running inside GitHub Actions.
emit() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1=$2" >>"$GITHUB_OUTPUT"
  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)   AUTO_COMMIT=1; shift ;;
    --upstream) UPSTREAM_URL="$2"; shift 2 ;;
    --branch)   UPSTREAM_BRANCH="$2"; shift 2 ;;
    -h|--help)  sed -n '3,20p' "$0"; exit 0 ;;
    *)          die "unknown argument '$1'" ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"

[[ -z "$(git status --porcelain)" ]] ||
  die "working tree is not clean; commit or stash first"
[[ ! -e .git/MERGE_HEAD ]] ||
  die "a merge is already in progress; finish or abort it first"

# ---------------------------------------------------------------------------
# Fetch
# ---------------------------------------------------------------------------

if ! git remote get-url upstream >/dev/null 2>&1; then
  note "adding 'upstream' remote -> $UPSTREAM_URL"
  git remote add upstream "$UPSTREAM_URL"
fi

note "fetching upstream/$UPSTREAM_BRANCH"
git fetch --quiet upstream "$UPSTREAM_BRANCH"

target="upstream/$UPSTREAM_BRANCH"
if git merge-base --is-ancestor "$target" HEAD; then
  note "already up to date with $target; nothing to do"
  emit updated false
  exit 0
fi

new_commits=$(git rev-list --count HEAD.."$target")
note "merging $target ($new_commits new commit(s))"

# ---------------------------------------------------------------------------
# Merge, resolving insertion-vs-insertion conflicts by keeping both sides
# ---------------------------------------------------------------------------

resolved=()
if ! git merge --no-commit --no-ff "$target" >/dev/null 2>&1; then
  mapfile -t conflicted < <(git diff --name-only --diff-filter=U)
  [[ ${#conflicted[@]} -gt 0 ]] ||
    { git merge --abort; die "merge failed for a reason other than conflicts"; }

  for file in "${conflicted[@]}"; do
    allowed=0
    for candidate in "${UNION_FILES[@]}"; do
      [[ "$file" == "$candidate" ]] && allowed=1
    done
    if [[ $allowed -eq 0 ]]; then
      git merge --abort
      die "'$file' conflicted but is not in the union list.
     This fork is not supposed to modify that file, so the conflict is real.
     Resolve it by hand:  git merge $target"
    fi

    tmp=$(mktemp -d)
    git show ":1:$file" >"$tmp/base"   2>/dev/null || : >"$tmp/base"
    git show ":2:$file" >"$tmp/ours"
    git show ":3:$file" >"$tmp/theirs"
    git merge-file --union -p "$tmp/ours" "$tmp/base" "$tmp/theirs" >"$file"
    rm -rf "$tmp"
    git add "$file"
    resolved+=("$file")
  done
fi

# ---------------------------------------------------------------------------
# Verify -- a union merge never reports failure, so this is the real safety net
# ---------------------------------------------------------------------------

abort() {
  echo "error: $*" >&2
  echo "       aborting the merge; resolve by hand with: git merge $target" >&2
  git merge --abort 2>/dev/null || git reset --hard --quiet HEAD
  exit 1
}

note "verifying merged tree"

if grep -rInE '^(<{7}|={7}|>{7})( |$)' --exclude-dir=.git . >/dev/null 2>&1; then
  abort "conflict markers left in the tree"
fi

bash -n entrypoint.sh || abort "entrypoint.sh is not valid bash after merging"
for f in glb/*.sh; do
  bash -n "$f" || abort "$f is not valid bash after merging"
done
python3 -m py_compile glb/postprocess.py 2>/dev/null ||
  abort "glb/postprocess.py does not compile after merging"
rm -rf glb/__pycache__

# A union merge duplicates lines when upstream edits one next to ours, so check
# every marker appears exactly once rather than merely being present.
for file in "${!REQUIRED_ONCE[@]}"; do
  IFS='|' read -ra markers <<<"${REQUIRED_ONCE[$file]}"
  for marker in "${markers[@]}"; do
    count=$(grep -cFx -- "$marker" "$file" || true)
    [[ "$count" == "1" ]] ||
      abort "expected '$marker' exactly once in $file, found $count"
  done
done

# Duplicate input keys are the way a bad union merge shows up in action.yml.
dupes=$(grep -oE '^  [a-z0-9_]+:' action.yml | sort | uniq -d || true)
[[ -z "$dupes" ]] || abort "duplicate keys in action.yml:
$dupes"

if command -v python3 >/dev/null; then
  python3 - <<'PY' || abort "action.yml is not parseable YAML after merging"
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)  # PyYAML absent; the grep checks above still ran
yaml.safe_load(open("action.yml"))
PY
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

emit updated true
emit commits "$new_commits"
emit resolved "${resolved[*]:-}"

if [[ ${#resolved[@]} -gt 0 ]]; then
  note "auto-resolved by keeping both sides: ${resolved[*]}"
  echo "    Review the merged regions before pushing:"
  for file in "${resolved[@]}"; do
    echo "      git diff --cached -- $file"
  done
else
  note "merged cleanly, no conflicts"
fi

if [[ $AUTO_COMMIT -eq 1 ]]; then
  git commit --no-edit --quiet
  note "committed $(git rev-parse --short HEAD)"
else
  note "merge staged but not committed; finish with: git commit --no-edit"
fi
