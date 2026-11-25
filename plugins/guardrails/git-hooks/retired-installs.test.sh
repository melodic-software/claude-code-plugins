#!/usr/bin/env bash
# Contract tests for plugins/guardrails/retirements.yaml: the hooks the retired
# `apply install-commit-msg` and `apply install-pre-commit-content` actions wrote
# into .git/hooks/ are detected by the plugin's check-retirements.sh copy and
# cleaned one record at a time, while a user's own hook and the hooks
# `apply install-git-hooks` installs in their place are left alone.
# test-scope: plugins/guardrails/retirements.yaml plugins/guardrails/lib/check-retirements.sh plugins/guardrails/lib/git-hooks/install.mjs
# test-scope: plugins/guardrails/git-hooks/reference-verify.sh plugins/guardrails/hooks/*.sh plugins/guardrails/lib/verification/*.sh
# test-scope: plugins/guardrails/git-hooks/pre-push-content.sh plugins/guardrails/git-hooks/content-scan.sh plugins/guardrails/git-hooks/entries.json
# test-scope: plugins/guardrails/.claude-plugin/plugin.json
# test-scope: plugins/guardrails/git-hooks/commit-msg-convention.sh
# test-scope: plugins/guardrails/git-hooks/pre-commit-content.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR
# Env-supplied config (a caller's core.hooksPath, say) would reach every repo below.
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
MANIFEST="$PLUGIN/retirements.yaml"
HELPER="$PLUGIN/lib/check-retirements.sh"
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

# shellcheck source=../lib/git-hooks-test-helpers.sh
source "$PLUGIN/lib/git-hooks-test-helpers.sh"

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

RV_ASSETS="hooks/run-guards.sh hooks/abort-boundary.sh hooks/cli-flag-verify.sh
hooks/skill-reference-verify.sh hooks/stale-path-verify.sh lib/verification/verify-cli-flag.sh
lib/verification/cli-flag-cache.sh"
RV_LOCAL="guardrails-r005 guardrails-r006 guardrails-r007 guardrails-r008 guardrails-r009 guardrails-r010 guardrails-r011 guardrails-r012 guardrails-r013 guardrails-r014"
RV_SHARED="guardrails-r015 guardrails-r016 guardrails-r017 guardrails-r018 guardrails-r019 guardrails-r020 guardrails-r021 guardrails-r022 guardrails-r023 guardrails-r024"
reference_verify_install() {
  local d="$1" a
  mkdir -p "$d/pre-push.d" "$d/guardrails"
  printf 'guardrails/reference-verify.sh\n' >"$d/pre-push.d/guardrails.reference-verify"
  {
    printf '#!/bin/sh\n# guardrails reference-verify sha256:%064d\n' 0
    tail -n +2 "$PLUGIN/git-hooks/reference-verify.sh"
  } >"$d/guardrails/reference-verify.sh"
  for a in $RV_ASSETS; do cp "$PLUGIN/$a" "$d/guardrails/"; done
  printf '# shellcheck shell=bash\n# Shared hook utility library for this marketplace'\''s hook plugins.\n' \
    >"$d/guardrails/hook-utils.sh"
}

clean_all() {
  local id rc=0
  for id in "$@"; do [[ "$(clean "$id")" == 0 ]] || rc=1; done
  echo "$rc"
}

new_repo
reference_verify_install "$REPO/.git/hooks"
expect "every file of a local reference-verify install is detected" "1|$RV_LOCAL" "$(detect)"
expect "the marker cleans on its own" 0 "$(clean guardrails-r005)"
expect "cleaning the marker removes only the marker" \
  "1|${RV_LOCAL#guardrails-r005 }" "$(detect)"
# shellcheck disable=SC2086 # one id per word
expect "the script and every asset clean" 0 "$(clean_all ${RV_LOCAL#guardrails-r005 })"
expect "nothing is left after the reference-verify cleanups" "0|" "$(detect)"

new_repo
mkdir -p "$REPO/.git/hooks/pre-push.d" "$REPO/.git/hooks/guardrails"
printf 'my-tools/check.sh\n' >"$REPO/.git/hooks/pre-push.d/guardrails.reference-verify"
printf '#!/bin/sh\n# my own reference check\nexit 0\n' >"$REPO/.git/hooks/guardrails/reference-verify.sh"
printf '#!/bin/sh\n# my own runner\nexit 0\n' >"$REPO/.git/hooks/guardrails/run-guards.sh"
expect "a user's own files at the reference-verify paths are not leftovers" "0|" "$(detect)"
expect "a user's own file at a recorded path is not cleaned" 1 "$(clean guardrails-r007)"
expect "the user's own file is still there" yes "$(test -f "$REPO/.git/hooks/guardrails/run-guards.sh" && echo yes)"

SL='/'
FAKE_LINUX="${SL}home${SL}alice${SL}projects${SL}demo${SL}src${SL}main.sh"
new_repo
git init -q --bare -b main "$WORK/r$n.git"
git -C "$REPO" config user.name t
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" commit -q --allow-empty -m seed
git -C "$REPO" remote add origin "$WORK/r$n.git"
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
git -C "$REPO" remote set-head origin main >/dev/null
node "$INSTALL" copy --scope local --repo "$REPO" >/dev/null 2>&1
reference_verify_install "$REPO/.git/hooks"
expect "a reference-verify install beside the current entries is detected alone" "1|$RV_LOCAL" "$(detect)"
# shellcheck disable=SC2086 # one id per word
expect "the reference-verify files clean beside the current entries" 0 "$(clean_all $RV_LOCAL)"
h="$REPO/.git/hooks"
expect "the current entries' files are untouched" yes \
  "$(test -f "$h/pre-push" && test -f "$h/pre-push.d/guardrails.pre-push-content" &&
    test -f "$h/guardrails/pre-push-content.sh" && test -f "$h/guardrails/content-scan.sh" &&
    test -f "$h/guardrails/check-lib.sh" && test -f "$h/guardrails/secret-patterns.sh" &&
    test -f "$h/guardrails/hardcoded-path-patterns.sh" && test -f "$h/guardrails/machine-path-patterns.sh" && echo yes)"
printf 'see %s here\n' "$FAKE_LINUX" >"$REPO/notes.md"
git -C "$REPO" add notes.md
git -C "$REPO" commit -q --no-verify -m path
push_err="$(git -C "$REPO" push -q origin main 2>&1 >/dev/null)"
push_rc=$?
expect "the next push still runs pre-push-content, which blocks the path" 1 "$push_rc"
expect "the push names the path finding" yes "$(grep -q 'machine-specific path' <<<"$push_err" && echo yes)"
expect "the push names no missing registered script" no "$(grep -q 'registered but missing' <<<"$push_err" && echo yes || echo no)"

new_repo
git -C "$REPO" config user.name t
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" commit -q --allow-empty -m seed
reference_verify_install "$REPO/.git/hooks"
git -C "$REPO" worktree add -q -b side "$WORK/wt$n" 2>/dev/null
main_repo="$REPO"
REPO="$WORK/wt$n"
expect "a linked worktree finds the local install in the common git dir" "1|$RV_LOCAL" "$(detect)"
expect "a linked worktree cleans the common git dir's marker" 0 "$(clean guardrails-r005)"
expect "the marker is gone from the main checkout's hooks" no \
  "$(test -f "$main_repo/.git/hooks/pre-push.d/guardrails.reference-verify" && echo yes || echo no)"

new_repo
reference_verify_install "$REPO/.githooks"
git -C "$REPO" config core.hooksPath .githooks
expect "every file of a shared reference-verify install is detected" "1|$RV_SHARED" "$(detect)"
# shellcheck disable=SC2086 # one id per word
expect "every shared reference-verify file cleans" 0 "$(clean_all $RV_SHARED)"
expect "nothing is left after the shared cleanups" "0|" "$(detect)"

echo "retired-installs: $PASS passed, $FAIL failed"
((FAIL == 0))
