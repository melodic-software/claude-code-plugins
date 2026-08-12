#!/usr/bin/env bash
# Regression tests for permission-state.sh (self-contained — ships with the plugin).
#
# Every run is fully fixtured: project root, start directory, managed policy, and
# the user home all point into a temp tree, with CLAUDE_CONFIG_DIR unset. No test
# reads or writes the operator's real ~/.claude or the machine's real managed
# policy — which is also why the Windows registry surface is exercised through
# its key-list seam rather than against a deployed policy.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/permission-state.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
count_matching() { printf '%s\n' "$1" | grep -cE "$2"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# --- Fixture tree: all five scopes populated ---------------------------------
FX="$TEST_TMPDIR/fx"
mkdir -p "$FX/proj/.claude" "$FX/home/.claude" "$FX/policy/managed-settings.d" "$FX/startdir/.claude"
jq -n '{permissions:{allow:["Bash(git status)"],deny:["WebFetch"]}}' >"$FX/proj/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(npm test)"]}}' >"$FX/proj/.claude/settings.local.json"
jq -n '{permissions:{allow:["Bash(python*)"]}}' >"$FX/home/.claude/settings.json"
jq -n '{permissions:{deny:["Read(./.env)"]}}' >"$FX/policy/managed-settings.json"
jq -n '{permissions:{ask:["Bash(rm *)"]}}' >"$FX/policy/managed-settings.d/20-second.json"
jq -n '{permissions:{ask:["Bash(dd *)"]}}' >"$FX/policy/managed-settings.d/10-first.json"
jq -n '{permissions:{allow:["Bash(ls)"]}}' >"$FX/policy/managed-settings.d/.hidden.json"
jq -n '{permissions:{allow:["Bash(ls)"]}}' >"$FX/startdir/.claude/settings.local.json"

run() {
  env -u CLAUDE_CONFIG_DIR \
    HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="${STUB_REGISTRY_KEYS:-}" \
    PERMISSION_STATE_PLIST_DOMAIN="${STUB_PLIST_DOMAIN:-}" \
    bash "$SCRIPT" "$@"
}

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: every file scope appears EXACTLY once ---------------------------
# Exactly one, not "at least one": a count of >=1 passes on project+local alone
# and leaves the two scopes this reader exists to add entirely unverified.
rc=0
OUT=$(run) || rc=$?
assert_exit "full run exits 0" 0 "$rc"
assert_eq "user scope appears exactly once" "1" "$(count_matching "$OUT" '^user ')"
assert_eq "project scope appears exactly once" "1" "$(count_matching "$OUT" '^project ')"
assert_eq "local scope appears exactly once" "1" "$(count_matching "$OUT" '^local ')"
assert_eq "start-directory scope appears exactly once" "1" "$(count_matching "$OUT" '^startdir-local ')"

# --- Case 3: every managed SURFACE appears exactly once, on every OS ----------
# The managed scope is four surfaces with different costs. Asserting a single
# aggregate "managed" row would pass with three of the four never attempted.
assert_eq "managed base file surface" "1" "$(count_matching "$OUT" '^managed file ')"
assert_eq "managed drop-in directory surface" "1" "$(count_matching "$OUT" '^managed dropin-dir ')"
assert_eq "managed registry surface" "1" "$(count_matching "$OUT" '^managed registry ')"
assert_eq "managed preferences-domain surface" "1" "$(count_matching "$OUT" '^managed plist ')"

# --- Case 4: rules are inventoried per scope and kind ------------------------
assert_contains "managed deny rule" "$OUT" "rule managed file deny Read(./.env)"
assert_contains "user allow rule" "$OUT" "rule user settings allow Bash(python*)"
assert_contains "project allow rule" "$OUT" "rule project settings allow Bash(git status)"
assert_contains "project deny rule" "$OUT" "rule project settings deny WebFetch"
assert_contains "local allow rule" "$OUT" "rule local settings allow Bash(npm test)"
assert_contains "start-directory allow rule" "$OUT" "rule startdir-local settings allow Bash(ls)"

# --- Case 5: drop-ins in documented order, dotfiles ignored ------------------
# "all *.json files in the drop-in directory are sorted alphabetically and merged
# on top… Hidden files starting with . are ignored." Order is load-bearing: later
# files override earlier ones, so a reader that emits them out of order hands the
# merge step the wrong answer.
dropins=$(printf '%s\n' "$OUT" | grep -oE '^managed dropin-file:[^ ]+' | sed 's/^managed dropin-file://')
assert_eq "drop-ins emitted in alphabetical order" "$(printf '10-first.json\n20-second.json')" "$dropins"
assert_not_contains "hidden drop-in ignored" "$OUT" ".hidden.json"

# --- Case 6: --scopes suppresses rule records only ---------------------------
OUT_SCOPES=$(run --scopes)
assert_eq "no rule records under --scopes" "0" "$(count_matching "$OUT_SCOPES" '^rule ')"
assert_eq "surface records survive --scopes" "1" "$(count_matching "$OUT_SCOPES" '^managed file ')"

# --- Case 7: server-managed settings are disclosed, never implied absent -----
assert_contains "server-managed settings disclosed" "$OUT" "Server-managed settings"

# --- Case 8: status vocabulary distinguishes absent from malformed -----------
BAD="$TEST_TMPDIR/bad"
mkdir -p "$BAD/proj/.claude" "$BAD/home/.claude" "$BAD/startdir"
printf '{invalid\n' >"$BAD/proj/.claude/settings.json"
OUT_BAD=$(env -u CLAUDE_CONFIG_DIR HOME="$BAD/home" \
  PERMISSION_STATE_FIXTURE_DIR="$BAD/proj" \
  PERMISSION_STATE_STARTDIR="$BAD/startdir" \
  PERMISSION_STATE_MANAGED_PATH="$BAD/policy/managed-settings.json" \
  PERMISSION_STATE_REGISTRY_KEYS="" PERMISSION_STATE_PLIST_DOMAIN="" \
  bash "$SCRIPT")
assert_contains "malformed settings reported as invalid-json" "$OUT_BAD" "project settings invalid-json"
assert_contains "missing settings reported as absent" "$OUT_BAD" "user settings absent"
assert_contains "missing managed file reported as absent" "$OUT_BAD" "managed file absent"
assert_eq "a malformed file contributes no rules" "0" "$(count_matching "$OUT_BAD" '^rule project ')"

# --- Case 9: the start-directory copy is never double-counted ----------------
# When the session starts at the repository root the two paths are the same file.
# Reporting it twice would claim two live rule sources where there is one.
OUT_SAME=$(env -u CLAUDE_CONFIG_DIR HOME="$FX/home" \
  PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
  PERMISSION_STATE_STARTDIR="$FX/proj" \
  PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
  PERMISSION_STATE_REGISTRY_KEYS="" PERMISSION_STATE_PLIST_DOMAIN="" \
  bash "$SCRIPT")
assert_contains "same directory reported not-applicable" "$OUT_SAME" "startdir-local settings not-applicable"
assert_eq "its rules are not counted twice" "1" "$(count_matching "$OUT_SAME" '^rule local settings allow Bash\(npm test\)')"

# --- Case 10: an unresolvable user scope is announced ------------------------
OUT_NOHOME=$(env -u CLAUDE_CONFIG_DIR -u HOME \
  PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
  PERMISSION_STATE_STARTDIR="$FX/startdir" \
  PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
  PERMISSION_STATE_REGISTRY_KEYS="" PERMISSION_STATE_PLIST_DOMAIN="" \
  bash "$SCRIPT")
assert_contains "unresolvable user scope is skipped, not absent" "$OUT_NOHOME" "user settings skipped"
assert_contains "and says why" "$OUT_NOHOME" "neither CLAUDE_CONFIG_DIR nor HOME"

# --- Case 11: optional platform legs degrade visibly, core survives ----------
# A stub PATH holding every tool the script needs EXCEPT `reg`. Not a bare
# `PATH=`: that makes the interpreter itself unresolvable (exit 127, "command not
# found"), which would "pass" for a reason unrelated to the tool under test.
#
# Each entry is a wrapper that execs the real binary at its absolute path,
# deliberately NOT a copy: an MSYS binary copied out of /usr/bin loses the
# msys-2.0.dll sitting beside it and fails to start, which would make this case
# "pass" by breaking every tool instead of the one under test.
STUB="$TEST_TMPDIR/stub-path"
mkdir -p "$STUB"
real_bash="$(command -v bash)"
for tool in jq git tr find sort sed head grep cat mktemp rm; do
  src="$(command -v "$tool" 2>/dev/null)" || continue
  [[ -n "$src" ]] || continue
  printf '#!%s\nexec "%s" "$@"\n' "$real_bash" "$src" >"$STUB/$tool"
  chmod +x "$STUB/$tool"
done
rc=0
# portability-ok: `\S` in the Windows registry path strings below are literal
# backslash-S characters in fixture data, not GNU regex escapes.
OUT_NOREG=$(env -u CLAUDE_CONFIG_DIR PATH="$STUB" HOME="$FX/home" \
  PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
  PERMISSION_STATE_STARTDIR="$FX/startdir" \
  PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
  PERMISSION_STATE_REGISTRY_KEYS='HKLM\SOFTWARE\Policies\ClaudeCode' \
  PERMISSION_STATE_PLIST_DOMAIN="" \
  "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "missing optional tool does not fail the run" 0 "$rc"
assert_contains "registry surface marked skipped" "$OUT_NOREG" "managed registry skipped"
assert_contains "and the skip is announced" "$OUT_NOREG" "'reg' is not on PATH"
assert_contains "portable core still read: base file" "$OUT_NOREG" "managed file present"
assert_contains "portable core still read: drop-in dir" "$OUT_NOREG" "managed dropin-dir present"
assert_contains "other scopes unaffected" "$OUT_NOREG" "rule user settings allow Bash(python*)"

# --- Case 12: registry key selection stops at the first key that EXISTS -------
# HKCU is documented as lowest policy priority, used only when no admin-level
# source exists, so an existing higher-priority key must end the search even when
# its Settings value cannot be read — otherwise a stray admin-level key lets
# user-level policy be reported as the managed policy.
#
# Read-only, and writes nothing to the registry: the fixture keys are one that
# cannot exist and HKCU\SOFTWARE, which exists on every Windows install and
# carries no Settings value — exactly the key-present/value-absent case.
if command -v reg >/dev/null 2>&1; then
  # portability-ok: `\S` in the printf registry key strings are literal path
  # separators in Windows registry paths, not GNU regex escapes.
  OUT_REG=$(env -u CLAUDE_CONFIG_DIR HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="$(printf 'HKCU\\SOFTWARE\\ClaudeCodeNoSuchKeyExists\nHKCU\\SOFTWARE')" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$SCRIPT")
  assert_contains "an absent key is skipped, the existing one is selected" "$OUT_REG" "managed registry unreadable HKCU\\SOFTWARE" # portability-ok: Windows registry path string in a test fixture, not a regex construct
  assert_contains "a key with no readable value is not a licence to fall through" "$OUT_REG" "Lower-priority policy keys are NOT consulted"
  assert_eq "no rules are claimed from an unreadable key" "0" "$(count_matching "$OUT_REG" '^rule managed registry ')"

  # portability-ok: Windows registry path strings in the printf below are fixture data, not regex constructs.
  OUT_REG_NONE=$(env -u CLAUDE_CONFIG_DIR HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="$(printf 'HKCU\\SOFTWARE\\ClaudeCodeNoSuchKeyExists\nHKCU\\SOFTWARE\\ClaudeCodeAlsoAbsent')" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$SCRIPT")
  assert_contains "no policy keys at all reports absent" "$OUT_REG_NONE" "managed registry absent"
else
  pass "registry key selection (skipped — reg not on PATH)"
  pass "registry absence reporting (skipped — reg not on PATH)"
fi

# --- Case 13: jq is required for correctness ---------------------------------
# The jq gate runs before any external tool, so an EMPTY stub dir is enough here;
# bash is invoked by absolute path so the empty PATH cannot hide the interpreter.
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "exit 2 when jq missing" 2 "$rc"
assert_contains "jq required message" "$err_out" "jq required"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
