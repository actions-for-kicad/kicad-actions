#!/usr/bin/env bash
#
# Configure this clone to publish under the org identity, and install the hooks
# that enforce it.
#
# Both pieces are per-clone: git deliberately does not let a repository ship
# executable hooks or an identity that a fresh clone picks up on its own. That
# is why this is a script you run rather than a file that just works, and why
# the CI guard exists as the backstop for a clone where nobody ran it.
#
# Safe to re-run; it only ever overwrites its own settings.
#
# Usage:
#   scripts/install-hooks.sh [--check]
#
#   --check   report whether this clone is configured, without changing it
#
set -euo pipefail

ORG_NAME="HardByte Prototyping"
ORG_EMAIL="dev@hardbyte-gmbh.de"
HOOKS_PATH="scripts/hooks"

CHECK_ONLY=0

die() { echo "error: $*" >&2; exit 1; }
note() { echo "==> $*"; }

case "${1:-}" in
  "")        ;;
  --check)   CHECK_ONLY=1 ;;
  -h|--help) sed -n '3,18p' "$0"; exit 0 ;;
  *)         die "unknown argument '$1'" ;;
esac

cd "$(git rev-parse --show-toplevel)"

if [[ $CHECK_ONLY -eq 1 ]]; then
  ok=0
  [[ "$(git config --local --get user.name  || true)" == "$ORG_NAME"  ]] || { echo "user.name not set to the org identity" >&2; ok=1; }
  [[ "$(git config --local --get user.email || true)" == "$ORG_EMAIL" ]] || { echo "user.email not set to the org identity" >&2; ok=1; }
  [[ "$(git config --local --get core.hooksPath || true)" == "$HOOKS_PATH" ]] || { echo "core.hooksPath not pointing at $HOOKS_PATH" >&2; ok=1; }
  [[ $ok -eq 0 ]] && note "this clone is configured" || echo "run scripts/install-hooks.sh to fix" >&2
  exit $ok
fi

# Repo-local, so it wins over whatever --global says. The leak this guards
# against was exactly a clone that had no local override and fell through to a
# personal global identity.
git config --local user.name  "$ORG_NAME"
git config --local user.email "$ORG_EMAIL"
note "identity set: $ORG_NAME <$ORG_EMAIL>"

# Point git at the tracked hooks rather than copying them into .git/hooks, so
# a later change to a hook takes effect on pull instead of silently running the
# stale copy someone installed months ago.
git config --local core.hooksPath "$HOOKS_PATH"
chmod +x "$HOOKS_PATH"/* scripts/*.sh
note "hooks enabled: core.hooksPath -> $HOOKS_PATH"

note "verifying"
scripts/check-identity.sh --config
