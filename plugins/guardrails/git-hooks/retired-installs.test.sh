#!/usr/bin/env bash
# Contract tests for plugins/guardrails/retirements.yaml: the hooks the retired
# `apply install-commit-msg` and `apply install-pre-commit-content` actions wrote
# into .git/hooks/ are detected by the plugin's check-retirements.sh copy and
# cleaned one record at a time, while a user's own hook and the hooks
# `apply install-git-hooks` installs in their place are left alone.
# test-scope: plugins/guardrails/retirements.yaml plugins/guardrails/lib/check-retirements.sh plugins/guardrails/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
MANIFEST="$PLUGIN/retirements.yaml"
HELPER="$PLUGIN/lib/check-retirements.sh"
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
}

# detect -> "<rc>|<ids, space-separated>"
detect() {
  local rows rc
  rows="$(bash "$HELPER" --manifest "$MANIFEST" --root "$REPO" 2>/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(cut -f1 <<<"$rows" | sort | tr '\n' ' ' | sed 's/ $//')"
}

clean() { # <id> [--i-migrated] -> exit code
  bash "$HELPER" --manifest "$MANIFEST" --root "$REPO" --clean "$@" >/dev/null 2>&1
  echo $?
}

# The retired installs, as their recipes wrote them: each hook's second line is
# its sentinel, the resolver is the plugin's resolve-convention-pattern.sh, and
# the content hook's libraries sit in guardrails-content-lib/.
old_installs() {
  local h="$REPO/.git/hooks"
  printf '#!/usr/bin/env bash\n# guardrails-commit-msg-convention v1\nexit 0\n' >"$h/commit-msg"
  cp "$PLUGIN/hooks/resolve-convention-pattern.sh" "$h/guardrails-resolve-convention.sh"
  printf '#!/usr/bin/env bash\n# guardrails-pre-commit-content-invariants v1\nexit 0\n' >"$h/pre-commit"
  mkdir -p "$h/guardrails-content-lib/secret-detection" "$h/guardrails-content-lib/path-detection"
  cp "$PLUGIN/lib/secret-detection/secret-patterns.sh" "$h/guardrails-content-lib/secret-detection/"
  chmod +x "$h/commit-msg" "$h/pre-commit"
}

new_repo
expect "a clone without the retired installs has no leftover" "0|" "$(detect)"

new_repo
old_installs
expect "every retired install is detected" \
  "1|guardrails-r001 guardrails-r002 guardrails-r003 guardrails-r004" "$(detect)"
expect "a migrate record refuses to clean without --i-migrated" 2 "$(clean guardrails-r001)"
expect "the retired commit-msg hook cleans once migrated" 0 "$(clean guardrails-r001 --i-migrated)"
expect "the resolver copy cleans" 0 "$(clean guardrails-r002)"
expect "the retired pre-commit hook cleans once migrated" 0 "$(clean guardrails-r003 --i-migrated)"
expect "the content-lib directory cleans" 0 "$(clean guardrails-r004)"
expect "nothing is left after the four cleanups" "0|" "$(detect)"
expect "the hooks directory itself survives the cleanup" yes "$(test -d "$REPO/.git/hooks" && echo yes)"

new_repo
printf '#!/bin/sh\n# my own commit-msg check\nexit 0\n' >"$REPO/.git/hooks/commit-msg"
printf '#!/bin/sh\nexec my-linter\n' >"$REPO/.git/hooks/pre-commit"
expect "a user's own hooks at the same paths are not leftovers" "0|" "$(detect)"

new_repo
git -C "$REPO" config user.name t
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" commit -q --allow-empty -m seed
node "$INSTALL" copy --scope local --repo "$REPO" >/dev/null 2>&1
expect "install-git-hooks wrote its plain dispatchers" yes \
  "$(test -f "$REPO/.git/hooks/commit-msg" && test -f "$REPO/.git/hooks/pre-commit" && echo yes)"
expect "the hooks install-git-hooks writes are not leftovers" "0|" "$(detect)"

echo "retired-installs: $PASS passed, $FAIL failed"
((FAIL == 0))
