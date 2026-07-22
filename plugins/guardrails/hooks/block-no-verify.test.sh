#!/usr/bin/env bash
# Contract test for block-no-verify.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-no-verify.sh"
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

# --- Form 1: --no-verify / -n on git commit ---------------------------------
run "git commit --no-verify (blocked)" "git commit --no-verify -m test" 2
run "git commit -n (blocked)" "git commit -n -m test" 2
run "cd foo && git commit --no-verify (compound, blocked)" "cd foo && git commit --no-verify -m test" 2
run "git commit -m test (allowed)" "git commit -m test" 0
run "git push --no-verify (blocked)" "git push --no-verify" 2
run "quoted --no-verify prose (allowed)" 'echo "git commit --no-verify is banned"' 0
run "echo git commit --no-verify (git as arg, allowed)" 'echo git commit --no-verify' 0

# --- Form 1b: core.hooksPath assignment -------------------------------------
run "git -c core.hooksPath=/dev/null commit (blocked)" "git -c core.hooksPath=/dev/null commit -m test" 2
run "git -c core.hookspath=/dev/null push (blocked)" "git -c core.hookspath=/dev/null push" 2
run "git commit -m core.hooksPath=/tmp (message literal, allowed)" \
  "git commit -m 'core.hooksPath=/tmp'" 0
run "cd foo && git -c core.hooksPath commit (compound, blocked)" "cd foo && git -c core.hooksPath=/dev/null commit -m test" 2
run "quoted core.hooksPath prose (allowed)" 'echo "git -c core.hooksPath=/dev/null commit"' 0

# --- Argv-faithful gate regressions (P3) ------------------------------------
# The shell removes quotes/escapes before git parses argv, so quoting the git
# executable, the subcommand, OR the flag must all still be caught.
run "git commit \"--no-verify\" (quoted flag, blocked)" \
  'git commit "--no-verify" -m test' 2
run "git commit --no-ver'ify' (partial-quote flag, blocked)" \
  "git commit --no-ver'ify' -m test" 2
run "git commit \"-n\" (quoted short flag, blocked)" \
  'git commit "-n" -m test' 2
run "git commit --no-\\verify (escaped flag, blocked)" \
  'git commit --no-\verify -m test' 2
run "\"git\" commit --no-verify (quoted executable, blocked)" \
  '"git" commit --no-verify -m test' 2
run "git \"commit\" --no-verify (quoted subcommand, blocked)" \
  'git "commit" --no-verify -m test' 2
run "g'i't commit --no-verify (split-quoted executable, blocked)" \
  "g'i't commit --no-verify -m test" 2
run "git -c \"core.hooksPath=…\" commit (quoted config, blocked)" \
  'git -c "core.hooksPath=/dev/null" commit -m test' 2
run "\"git\" -c core.hooksPath=… commit (quoted exec + config, blocked)" \
  '"git" -c core.hooksPath=/dev/null commit -m test' 2
run "git -c 'core.hooksPath=…' push (single-quoted config, blocked)" \
  "git -c 'core.hooksPath=/dev/null' push" 2

# --- Argv-faithful negatives — must NOT block (exit 0) ----------------------
run "echo \"git commit --no-verify\" (quoted arg, allowed)" \
  'echo "git commit --no-verify"' 0
run "echo 'use git commit --no-verify never' (quoted arg, allowed)" \
  "echo 'use git commit --no-verify never'" 0
run "echo \"a && git commit --no-verify\" (operator in quotes, allowed)" \
  'echo "a && git commit --no-verify"' 0
run "\"git commit\" --no-verify (command-not-found form, allowed)" \
  '"git commit" --no-verify -m test' 0
run "git commit -m \"explain --no-verify\" (flag in message value, allowed)" \
  'git commit -m "explain --no-verify"' 0

# --- [P2] git global options that consume an argument -----------------------
run "git -C . commit --no-verify (arg-consuming -C, blocked)" \
  'git -C . commit --no-verify -m test' 2
run "git --git-dir=/x commit --no-verify (=-form global, blocked)" \
  'git --git-dir=/x commit --no-verify -m test' 2
run "git --work-tree /tmp commit --no-verify (two-word global, blocked)" \
  'git --work-tree /tmp commit --no-verify -m test' 2
run "git -C . -c core.hooksPath=/dev/null push (blocked)" \
  'git -C . -c core.hooksPath=/dev/null push' 2

# --- [P2] short-option bundle -n --------------------------------------------
run "git commit -nm msg (n before arg-taking m, blocked)" \
  'git commit -nm msg' 2
run "git commit -vn (n after non-arg short, blocked)" \
  'git commit -vn -m test' 2
run "git commit -mn (m takes value 'n', allowed)" \
  'git commit -mn' 0
run "git commit -am fix (no n-flag, allowed)" \
  'git commit -am fix' 0

# --- [P2] wrappers (with options) transparently pass through ----------------
run "env -i git commit --no-verify (env + option, blocked)" \
  'env -i git commit --no-verify -m test' 2
run "nice git commit --no-verify (blocked)" \
  'nice git commit --no-verify -m test' 2
run "timeout 5 git commit --no-verify (positional-arg wrapper, blocked)" \
  'timeout 5 git commit --no-verify -m test' 2
run "timeout -s KILL 5 git commit --no-verify (option + duration, blocked)" \
  'timeout -s KILL 5 git commit --no-verify -m test' 2
run "command git commit --no-verify (builtin prefix, blocked)" \
  'command git commit --no-verify -m test' 2
run "if git commit --no-verify (shell keyword prefix, blocked)" \
  'if git commit --no-verify -m test; then echo ok; fi' 2
run "sudo -u x git commit --no-verify (wrapper option, blocked)" \
  'sudo -u x git commit --no-verify -m test' 2
run "nice -n 10 git commit --no-verify (nice -n option, blocked)" \
  'nice -n 10 git commit --no-verify -m test' 2
run "time -p git commit --no-verify (time -p option, blocked)" \
  'time -p git commit --no-verify -m test' 2
run "git commit -m --no-verify (message value, allowed)" \
  'git commit -m --no-verify' 0
run "git commit -m 'LEFTHOOK=0' (message literal, allowed)" \
  "git commit -m 'LEFTHOOK=0'" 0
run "env -S 'git commit --no-verify' (split-string operand, blocked)" \
  "env -S 'git commit --no-verify -m test'" 2
run "env -S'git commit --no-verify' (attached split-string, blocked)" \
  "env -S'git commit --no-verify -m test'" 2
run "env --split-string='git commit --no-verify' (long form, blocked)" \
  "env --split-string='git commit --no-verify -m test'" 2
run "eval git commit --no-verify (eval prefix, blocked)" \
  'eval git commit --no-verify -m test' 2
run "env -S 'ls -la' (split-string non-git, allowed)" \
  "env -S 'ls -la'" 0

# --- [P3] case-insensitive executable + .exe strip (OS-gated) ----------------
case "${OSTYPE:-}" in
msys* | cygwin* | win32) exp_win=2 ;; # Windows/MSYS folds case + strips .exe
*) exp_win=0 ;;                       # POSIX stays case-sensitive
esac
run "GIT commit --no-verify (uppercase exec, OS-gated)" \
  'GIT commit --no-verify -m test' "$exp_win"
run "git.exe commit --no-verify (.exe strip, OS-gated)" \
  'git.exe commit --no-verify -m test' "$exp_win"

# --- [P5 subset] ANSI-C $'…' + backslash-newline continuation ---------------
run "git commit \$'--no-verify' (ANSI-C plain, blocked)" \
  "git commit \$'--no-verify' -m test" 2
run "git commit \$'\\x2d\\x2dno-verify' (ANSI-C hex, blocked)" \
  "git commit \$'\\x2d\\x2dno-verify' -m test" 2
lc_cmd=$(printf 'git commit --no-\\\nverify -m test')
run "git commit --no-<backslash-newline>verify (continuation, blocked)" \
  "$lc_cmd" 2

# --- [P4] over-length command fails CLOSED (blocked) ------------------------
long_cmd="echo $(printf 'a%.0s' {1..20000})"
run "command over the parse cap (fail-closed, blocked)" \
  "$long_cmd" 2

# --- Form 2: hook-manager env-var bypass on git commit / push ---------------
run "LEFTHOOK=0 git commit (blocked)" "LEFTHOOK=0 git commit -m test" 2
run "LEFTHOOK=false git push (blocked)" "LEFTHOOK=false git push" 2
run "LEFTHOOK=FALSE git commit (blocked, uppercase)" "LEFTHOOK=FALSE git commit -m test" 2
run "LEFTHOOK=False git push (blocked, mixed case)" "LEFTHOOK=False git push origin main" 2
run "LEFTHOOK_SUFFIX=false git push (blocked, suffix var)" "LEFTHOOK_VERIFY_GATE_ENABLED=false git push" 2
run "cd foo && LEFTHOOK=0 git commit (compound, blocked)" "cd foo && LEFTHOOK=0 git commit -m test" 2

# --- Form 2 negatives — env-var alone or with non-git command must NOT block -
run "LEFTHOOK=0 echo foo (not git, allowed)" "LEFTHOOK=0 echo foo" 0

# Default manager set covers more than lefthook.
run "HUSKY=0 git commit (default set, blocked)" "HUSKY=0 git commit -m test" 2
run "HUSKY=false git push (default set, blocked)" "HUSKY=false git push" 2
run "PRE_COMMIT=0 git commit (default set, blocked)" "PRE_COMMIT=0 git commit -m test" 2
run "SIMPLE_GIT_HOOKS=false git commit (default set, blocked)" "SIMPLE_GIT_HOOKS=false git commit -m test" 2
run "UNKNOWNMGR=0 git commit (not in set, allowed)" "UNKNOWNMGR=0 git commit -m test" 0

# --- Form 2b: the hook-manager prefix set is configurable -------------------
run "custom prefix blocks its manager" "MYHOOKS=0 git commit -m test" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES="myhooks"
run "custom set replaces the default (lefthook now allowed)" "LEFTHOOK=0 git commit -m test" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES="myhooks"
run "regex metachars in a prefix value are sanitized, not injected" "MYHOOKS=0 git commit -m test" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES="my.*hooks,myhooks"
run "all-non-alphanumeric prefix value falls back to the full default set (husky still blocked)" "HUSKY=0 git commit -m test" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES="!!!"
run "LEFTHOOK=false ls (not git, allowed)" "LEFTHOOK=false ls" 0
run "LEFTHOOK=1 git commit (truthy value, allowed)" "LEFTHOOK=1 git commit -m test" 0
run "LEFTHOOK=true git push (truthy value, allowed)" "LEFTHOOK=true git push" 0

# --- Unrelated commands — always no-op --------------------------------------
run "git status (read-only, allowed)" "git status" 0
run "empty command (allowed)" "" 0
run "git push (no env-var, allowed)" "git push" 0

# --- Kill switch — disabled path is a clean no-op even on a bypass -----------
run "kill switch off → no-op despite --no-verify" "git commit --no-verify -m test" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED=false

# --- Telemetry: block emits a `blocked` envelope ----------------------------
TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(command_json 'git commit --no-verify -m test')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "block-no-verify"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: subject Bash:git" "$(jq -r '.data.subject' "$TEL")" "Bash:git"
  assert_contains "telemetry: form no-verify" "$(jq -r '.data.form' "$TEL")" "no-verify"
else
  bad "telemetry: no envelope written on block"
fi

report
