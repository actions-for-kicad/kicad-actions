#!/usr/bin/env bash
#
# Verify that everything this fork publishes carries the org identity.
#
# This fork is public. Upstream's commits are legitimately authored by many
# people, but every commit *this fork adds on top* is published as the org --
# a personal name or address in commit metadata is the thing being avoided.
#
# The check is an allowlist, not a blocklist: exactly one identity is accepted
# and everything else fails. A blocklist would have to name the addresses it
# rejects, which means writing the very thing we are keeping out of the repo
# into a tracked file, and it would still miss an identity nobody thought of.
#
# Content is not scanned. Every leak so far has been in metadata -- authorship,
# committership, and the tagger line on annotated tags -- while the files
# themselves were clean.
#
# Usage:
#   scripts/check-identity.sh                 # config + fork range + hb- tags
#   scripts/check-identity.sh --config        # only the identity git would use
#   scripts/check-identity.sh --commits       # only the fork range vs upstream
#   scripts/check-identity.sh --range RANGE   # only the commits in RANGE
#   scripts/check-identity.sh --tags          # only the annotated hb- tags
#
set -euo pipefail

ORG_NAME="HardByte Prototyping"
ORG_EMAIL="dev@hardbyte-gmbh.de"

UPSTREAM_URL="https://github.com/actions-for-kicad/kicad-actions"
UPSTREAM_BRANCH="main"

CHECK_CONFIG=0
CHECK_RANGE=0
CHECK_TAGS=0
RANGE=""

die() { echo "error: $*" >&2; exit 1; }
note() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CHECK_CONFIG=1; shift ;;
    --tags)    CHECK_TAGS=1; shift ;;
    --commits) CHECK_RANGE=1; shift ;;
    --range)   CHECK_RANGE=1; RANGE="${2:-}"; [[ -n "$RANGE" ]] || die "--range needs a revision range"; shift 2 ;;
    -h|--help) sed -n '3,24p' "$0"; exit 0 ;;
    *)         die "unknown argument '$1'" ;;
  esac
done

# No selector means all three.
if [[ $CHECK_CONFIG -eq 0 && $CHECK_RANGE -eq 0 && $CHECK_TAGS -eq 0 ]]; then
  CHECK_CONFIG=1; CHECK_RANGE=1; CHECK_TAGS=1
fi

cd "$(git rev-parse --show-toplevel)"

failed=0

# The fix is the same wherever the check fails from, so it is printed once,
# here, rather than repeated at each call site.
remedy() {
  cat >&2 <<EOF

  This clone is configured to commit under a different identity. Fix it with:

      scripts/install-hooks.sh

  which sets the repo-local identity and installs the hooks that make this
  check run before a commit is made and before anything is pushed. It is
  per-clone configuration, so a fresh clone needs it again.
EOF
}

# ---------------------------------------------------------------------------
# The identity git would actually use, right now, in this clone
# ---------------------------------------------------------------------------
#
# Read through 'git var' rather than 'git config': it resolves the same
# precedence a commit does, so an identity coming from the environment or from
# a global fallback is caught, not just one written in a config file.

if [[ $CHECK_CONFIG -eq 1 ]]; then
  for role in AUTHOR COMMITTER; do
    ident=$(git var "GIT_${role}_IDENT")
    # "Name <email> 1234567890 +0200" -> name and email
    name=${ident%% <*}
    email=${ident#*<}; email=${email%%>*}
    if [[ "$email" != "$ORG_EMAIL" || "$name" != "$ORG_NAME" ]]; then
      echo "error: ${role,,} identity is '$name <$email>'" >&2
      echo "       expected '$ORG_NAME <$ORG_EMAIL>'" >&2
      failed=1
    fi
  done
  [[ $failed -eq 0 ]] && note "identity ok: $ORG_NAME <$ORG_EMAIL>"
fi

# ---------------------------------------------------------------------------
# Commits
# ---------------------------------------------------------------------------

if [[ $CHECK_RANGE -eq 1 ]]; then
  if [[ -z "$RANGE" ]]; then
    # Default to this fork's own commits: everything HEAD has that upstream
    # does not. Upstream's own authors are out of scope and must not be touched.
    if ! git remote get-url upstream >/dev/null 2>&1; then
      note "adding 'upstream' remote -> $UPSTREAM_URL"
      git remote add upstream "$UPSTREAM_URL"
    fi
    git fetch --quiet upstream "$UPSTREAM_BRANCH"
    RANGE="upstream/$UPSTREAM_BRANCH..HEAD"
  fi

  # Split on '|': it cannot appear in an address, and a name containing one
  # would fail the comparison anyway, which is the correct outcome here.
  #
  # $RANGE is deliberately unquoted below: the pre-push hook passes multi-token
  # rev-list expressions such as "<sha> --not --remotes", which have to reach
  # git as separate arguments.
  bad=0
  count=0
  while IFS='|' read -r sha an ae cn ce; do
    [[ -n "$sha" ]] || continue
    count=$((count + 1))
    if [[ "$ae" != "$ORG_EMAIL" || "$ce" != "$ORG_EMAIL" ||
          "$an" != "$ORG_NAME"  || "$cn" != "$ORG_NAME" ]]; then
      echo "error: $sha  author: $an <$ae>  committer: $cn <$ce>" >&2
      bad=$((bad + 1))
    fi
  done < <(git log $RANGE --format="%H|%an|%ae|%cn|%ce")

  if [[ $bad -gt 0 ]]; then
    echo "error: $bad of $count commit(s) in $RANGE carry a non-org identity" >&2
    failed=1
  else
    note "commits ok: $count in $RANGE"
  fi
fi

# ---------------------------------------------------------------------------
# Annotated tags
# ---------------------------------------------------------------------------
#
# An annotated tag carries its own tagger line, which no commit check covers.
# The fork's pin tags are the 'hb-' ones; upstream's version tags are not ours
# to police.

if [[ $CHECK_TAGS -eq 1 ]]; then
  bad=0
  count=0
  while IFS='|' read -r tag type tname temail; do
    [[ -n "$tag" ]] || continue
    [[ "$type" == "tag" ]] || continue   # lightweight tags have no tagger
    count=$((count + 1))
    temail=${temail#<}; temail=${temail%>}
    if [[ "$temail" != "$ORG_EMAIL" || "$tname" != "$ORG_NAME" ]]; then
      echo "error: tag $tag  tagger: $tname <$temail>" >&2
      bad=$((bad + 1))
    fi
  done < <(git for-each-ref 'refs/tags/hb-*' \
             --format='%(refname:short)|%(objecttype)|%(taggername)|%(taggeremail)')

  if [[ $bad -gt 0 ]]; then
    echo "error: $bad of $count annotated hb- tag(s) carry a non-org identity" >&2
    failed=1
  else
    note "tags ok: $count annotated hb- tag(s)"
  fi
fi

if [[ $failed -ne 0 ]]; then
  remedy
  exit 1
fi
