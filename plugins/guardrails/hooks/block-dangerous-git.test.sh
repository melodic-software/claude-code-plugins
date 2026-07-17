#!/usr/bin/env bash
# Contract test for block-dangerous-git.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-dangerous-git.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# run <label> <command> <expected-exit> [extra-env NAME=VAL ...]
run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc
  env "$@" bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# --- push-force ---------------------------------------------------------------
run "git push --force (blocked)" "git push --force" 2
run "git push -f (blocked)" "git push -f origin main" 2
run "git push origin main --force (flag after operands, blocked)" "git push origin main --force" 2
run "git push -uf (bundled f, blocked)" "git push -uf origin main" 2
run "git push origin +HEAD:main (refspec force, blocked)" "git push origin +HEAD:main" 2
run "git push origin +feature (bare + refspec, blocked)" "git push origin +feature" 2
run "git push --mirror (force-updates all refs, blocked)" "git push --mirror backup" 2
run "git push --force-with-lease (safe force, allowed)" "git push --force-with-lease" 0
run "git push --force-with-lease=main (valued lease, allowed)" "git push --force-with-lease=main origin main" 0
run "git push --force-if-includes (allowed)" "git push --force-with-lease --force-if-includes" 0
run "git push (plain, allowed)" "git push" 0
run "git push -u origin main (allowed)" "git push -u origin main" 0
run "git push -o f (option value f, allowed)" "git push -o f origin main" 0
run "git push -ofoo (attached option value, allowed)" "git push -ofoo origin main" 0
run "cd x && git push --force (compound, blocked)" "cd x && git push --force" 2
run "quoted push --force prose (allowed)" 'echo "git push --force is banned"' 0

# --- reset-hard ---------------------------------------------------------------
run "git reset --hard (blocked)" "git reset --hard" 2
run "git reset --hard HEAD~1 (blocked)" "git reset --hard HEAD~1" 2
run "git reset --soft HEAD~1 (allowed)" "git reset --soft HEAD~1" 0
run "git reset (mixed, allowed)" "git reset" 0
run "git reset --keep (allowed)" "git reset --keep HEAD~1" 0
run "git commit -m 'reset --hard' (message literal, allowed)" "git commit -m 'reset --hard'" 0

# --- clean-force --------------------------------------------------------------
run "git clean -f (blocked)" "git clean -f" 2
run "git clean -fd (blocked)" "git clean -fd" 2
run "git clean -fdx (blocked)" "git clean -fdx" 2
run "git clean --force (blocked)" "git clean --force" 2
run "git clean -n (dry run, allowed)" "git clean -n" 0
run "git clean -nd (dry run bundle, allowed)" "git clean -nd" 0 # spellchecker:disable-line
run "git clean -n -fd (dry run disarms force, allowed)" "git clean -n -fd" 0
run "git clean -fdn (dry run in force bundle, allowed)" "git clean -fdn" 0
run "git clean --dry-run -f (long dry run, allowed)" "git clean --dry-run -f" 0

# --- checkout-dot / restore-dot ----------------------------------------------
run "git checkout . (blocked)" "git checkout ." 2
run "git checkout -- . (blocked)" "git checkout -- ." 2
run "git checkout .github/workflows (path-scoped, allowed)" "git checkout .github/workflows" 0
run "git checkout main (branch switch, allowed)" "git checkout main" 0
run "git checkout -b feat/x (new branch, allowed)" "git checkout -b feat/x" 0
run "git restore . (blocked)" "git restore ." 2
run "git restore -- . (blocked)" "git restore -- ." 2
run "git restore --worktree . (blocked)" "git restore --worktree ." 2
run "git restore --staged --worktree . (blocked)" "git restore --staged --worktree ." 2
run "git restore --staged . (index-only, allowed)" "git restore --staged ." 0
run "git restore path/file (path-scoped, allowed)" "git restore path/file" 0
run "git restore --source HEAD~1 file (source value, allowed)" "git restore --source HEAD~1 file" 0

# --- not blocked by design ----------------------------------------------------
run "git branch -D feat/x (reflog-recoverable, allowed)" "git branch -D feat/x" 0
run "git branch -d feat/x (safe delete, allowed)" "git branch -d feat/x" 0
run "git status (read-only, allowed)" "git status" 0
run "empty command (allowed)" "" 0

# --- argv-faithful regressions ------------------------------------------------
run "git push \"--force\" (quoted flag, blocked)" 'git push "--force"' 2
run "git push --for'ce' (partial-quote flag, blocked)" "git push --for'ce'" 2
run "\"git\" push --force (quoted executable, blocked)" '"git" push --force' 2
run "git \$'--force' push? no — push \$'--force' (ANSI-C flag, blocked)" "git push \$'--force'" 2
run "echo git push --force (git as argument, allowed)" "echo git push --force" 0
run "echo \"a && git reset --hard\" (operator in quotes, allowed)" 'echo "a && git reset --hard"' 0
run "grep 'git clean -f' notes.md (quoted pattern, allowed)" "grep 'git clean -f' notes.md" 0
run "git -C . push --force (arg-consuming global, blocked)" "git -C . push --force" 2
run "env -i git push --force (wrapper, blocked)" "env -i git push --force" 2
run "env -S 'git push --force' (split-string, blocked)" "env -S 'git push --force'" 2
run "env -S quoted flag (inner-quote split-string, blocked)" "env -S 'git push \"--force\"'" 2

# --- allow-list ---------------------------------------------------------------
run "allow-list push-force → allowed" "git push --force" 0 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force
run "allow-list push-force,reset-hard → reset allowed" "git reset --hard" 0 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force,reset-hard
run "allow-list push-force only → clean still blocked" "git clean -fd" 2 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force
run "allow-list empty → blocked" "git push --force" 2 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=

# --- kill switch ---------------------------------------------------------------
run "kill switch off → no-op despite push --force" "git push --force" 0 \
  HOOK_BLOCK_DANGEROUS_GIT_ENABLED=false

# --- over-length command fails CLOSED ------------------------------------------
long_cmd="echo $(printf 'a%.0s' {1..20000})"
run "command over the parse cap (fail-closed, blocked)" "$long_cmd" 2
run "allow-list cannot bypass the parse cap (still blocked)" "$long_cmd" 2 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=too-long

# --- telemetry: block emits a `blocked` envelope --------------------------------
TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(command_json 'git push --force')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "block-dangerous-git"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: subject Bash:git" "$(jq -r '.data.subject' "$TEL")" "Bash:git"
  assert_contains "telemetry: form push-force" "$(jq -r '.data.form' "$TEL")" "push-force"
else
  bad "telemetry: no envelope written on block"
fi

report
