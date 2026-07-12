#!/usr/bin/env bash
# Contract test for block-hook-bypass.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-hook-bypass.sh"
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

# --- Core bypass forms ------------------------------------------------------
run "cat > file (blocked)" "cat > foo.txt" 2
run "echo > file (blocked)" "echo hello > foo.txt" 2
run "python3 -c open write (blocked)" \
  "python3 -c \"open('x','w').write('a')\"" 2
run "git status (allowed)" "git status" 0
run "cat file (allowed)" "cat README.md" 0
run "python3 -c json parse (allowed)" \
  "python3 -c \"import json; print(json.loads('{}'))\"" 0

# --- Redirect false-positive regression -------------------------------------
# stderr/fd redirects + /dev/null discards are NOT file-write bypasses, even
# when an `echo` appears in the same compound command.
run "echo + 2>/dev/null (allowed)" \
  "echo done; grep -i pat file 2>/dev/null" 0
run "echo + 2>&1 (allowed)" "echo hi; ls foo 2>&1 | cat" 0
run "echo stdout to /dev/null (allowed)" "echo noise >/dev/null" 0
run "echo + find 2>/dev/null pipe (allowed)" \
  "echo scan; find . -name x 2>/dev/null | head" 0
# Real writes still blocked, including alongside a stderr suppressor (no hole).
run "echo append > file still blocked" "echo line >> real.txt" 2
run "echo > file with 2>/dev/null still blocked" \
  "echo data > real.txt 2>/dev/null" 2

# --- Executable-token vs quoted-argument detection --------------------------
# Prose or a commit message merely MENTIONING a bypass in a quoted span is
# documentation, not a Write/Edit bypass. The python write-indicator scan stays
# on the raw command, so a real `python3 -c "open(...)"` still blocks.
run "echo prose mentioning python3 -c open (allowed)" \
  "echo 'use python3 -c open() to write a file'" 0
run "commit msg mentioning python3 -c open (allowed)" \
  "git commit -m 'doc: do not use python3 -c open() writes'" 0
run "python3 -c single-quoted open write (blocked)" \
  "python3 -c 'open(\"x\",\"w\").write(\"a\")'" 2

# --- Case-insensitive command-token detection (matters on Windows) ----------
run "uppercase CAT > file (blocked)" "CAT > foo.txt" 2
run "uppercase ECHO > file (blocked)" "ECHO hello > foo.txt" 2

# --- Accepted string-matching floor -----------------------------------------
# A write inside a command substitution in double quotes is NOT caught — the
# strip treats the quoted span as inert, and catching it would re-block inert
# prose sharing the span. A genuine regression vs raw-match, accepted as the floor.
# shellcheck disable=SC2016  # literal $(...) is the command under test, not for expansion
run "write in command substitution (accepted floor — allowed)" \
  'echo "$(python3 -c '\''import pathlib'\'')"' 0

# --- Kill switch — disabled path is a clean no-op even on a bypass ----------
run "kill switch off → no-op despite cat > file" "cat > foo.txt" 0 \
  HOOK_BLOCK_HOOK_BYPASS_ENABLED=false

# --- Telemetry: block emits a `blocked` envelope ----------------------------
TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(command_json 'cat > foo.txt')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "block-hook-bypass"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: subject Bash:cat" "$(jq -r '.data.subject' "$TEL")" "Bash:cat"
  assert_contains "telemetry: form cat-redirect" "$(jq -r '.data.form' "$TEL")" "cat-redirect"
else
  bad "telemetry: no envelope written on block"
fi

report
