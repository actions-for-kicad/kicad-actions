#!/usr/bin/env bash
#
# Sync this fork from actions-for-kicad/kicad-actions.
#
# The GLB feature is insert-only in every file that is union-merged below: it
# adds lines and modifies no existing upstream line there (see
# docs/glb-export.md). That is what makes auto-resolution safe -- the only
# conflicts that can arise in those files are two insertions competing for the
# same anchor, and the answer is always "keep both", which is what a union
# merge does.
#
# The one deliberate exception is Dockerfile's FROM line, which this fork
# changes to the -full image tag because the plain tag ships no 3D model
# library. Dockerfile is not union-merged, so the exception costs nothing here:
# if upstream touches that line the merge conflicts and stops for a human,
# which is the correct outcome. The REQUIRED_ONCE marker below is what catches
# a hand-resolution that quietly takes upstream's side and drops the meshes.
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

# Files this fork also only inserts into, but where a union merge is not
# wanted: machine-interleaved prose reads worse than a human placing it. A
# conflict here is expected and benign -- it just has to be resolved by hand,
# so it gets a message saying so rather than one crying invariant breach.
MANUAL_FILES=(README.md)

# Markers proving the GLB feature survived the merge intact. Matched as whole
# lines, so the leading indentation is part of the marker.
declare -A REQUIRED_ONCE=(
  ["entrypoint.sh"]="source /glb/setup.sh|source /img/setup.sh|  source /glb/export.sh|    source /img/autoframe.sh|  source /img/webp.sh"
  ["action.yml"]="  pcb_output_glb:|  pcb_output_webp:"
  ["Dockerfile"]="COPY glb/ /glb/|COPY img/ /img/|FROM kicad/kicad:10.0-full|    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends webp \\"
  ["README.md"]="## \`pcb_output_glb\`"
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

# Defined before the merge starts: everything from here on has a merge in
# progress to unwind, the resolution loop below included.
abort() {
  echo "error: $*" >&2
  echo "       aborting the merge; resolve by hand with: git merge $target" >&2
  git merge --abort 2>/dev/null || git reset --hard --quiet HEAD
  exit 1
}

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
      manual=0
      for candidate in "${MANUAL_FILES[@]}"; do
        [[ "$file" == "$candidate" ]] && manual=1
      done
      git merge --abort
      if [[ $manual -eq 1 ]]; then
        # Distinguishable from an invariant breach, so CI can report it as the
        # routine merge it is rather than raising a false alarm.
        emit manual_conflict "$file"
        die "'$file' conflicted. This fork inserts into it, but its content is
     not union-merged, so this one is resolved by hand:  git merge $target"
      fi
      die "'$file' conflicted but is not in the union list.
     This fork is not supposed to modify that file, so the conflict is real.
     Resolve it by hand:  git merge $target"
    fi

    tmp=$(mktemp -d)
    # Stage 1 is legitimately absent for an add/add conflict, so an empty
    # base is correct there. Stages 2 and 3 are not optional: a modify/delete
    # conflict has one of them missing, and letting 'set -e' kill the script
    # here would leave MERGE_HEAD and a half-staged merge behind, wedging
    # every later run on the "merge already in progress" check.
    git show ":1:$file" >"$tmp/base"   2>/dev/null || : >"$tmp/base"
    git show ":2:$file" >"$tmp/ours"   2>/dev/null ||
      abort "'$file' has no staged 'ours' side (modify/delete conflict?); union merge does not apply"
    git show ":3:$file" >"$tmp/theirs" 2>/dev/null ||
      abort "'$file' has no staged 'theirs' side (upstream deleted or renamed it?); union merge does not apply"
    git merge-file --union -p "$tmp/ours" "$tmp/base" "$tmp/theirs" >"$file"
    rm -rf "$tmp"
    git add "$file"
    resolved+=("$file")
  done
fi

# ---------------------------------------------------------------------------
# Verify -- a union merge never reports failure, so this is the real safety net
# ---------------------------------------------------------------------------

note "verifying merged tree"

if grep -rInE '^(<{7}|={7}|>{7})( |$)' --exclude-dir=.git . >/dev/null 2>&1; then
  abort "conflict markers left in the tree"
fi

bash -n entrypoint.sh || abort "entrypoint.sh is not valid bash after merging"
for f in glb/*.sh img/*.sh; do
  bash -n "$f" || abort "$f is not valid bash after merging"
done
if command -v python3 >/dev/null; then
  # Compiled in memory: py_compile would drop __pycache__ into the tree,
  # and the traceback is the only thing that says *where* the syntax error is.
  for f in glb/postprocess.py img/autoframe.py; do
    py_err=$(python3 -c "f='$f'; compile(open(f).read(), f, 'exec')" 2>&1) ||
      abort "$f does not compile after merging:
$py_err"
  done
else
  echo "==> note: python3 absent, skipping the postprocess.py compile check" >&2
fi

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
