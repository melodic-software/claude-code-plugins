#!/usr/bin/env bash
# Regression tests for setup-check.sh: the layer rows, the tracked-file guard,
# the resolved references, and one row per collector adapter.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/setup-check.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# The apply script is the write side of the same skill; naming it keeps the
# suites of this skill selected together (setup-apply.py).
: "$SCRIPT_DIR/setup-apply.py"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$(printf '%s' "$2" | head -c 600)" ;;
  esac
}
# The table pads its subject column, so row assertions match a regex whose
# `+` absorbs the padding.
assert_row() {
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then
    pass "$1"
  else
    fail "$1" "matches: $3" "$(printf '%s' "$2" | head -c 600)"
  fi
}

home="$(mktemp -d)"
repo="$(mktemp -d)"
trap 'rm -rf "$home" "$repo"' EXIT

# 1. No config anywhere: every layer INFO absent, references from the bundled
#    defaults, one row per adapter, exit 0.
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
rc=$?
assert_eq "no config exits 0" 0 "$rc"
assert_contains "user-global layer absent" "$out" "INFO  layer user-global"
assert_contains "team layer absent" "$out" "INFO  layer team"
assert_row "bundled default reference" "$out" "reference file_lines +1000 \(layer: bundled default\)"
adapters="$(find "$PLUGIN_ROOT/scripts/collectors" -maxdepth 1 -name '*.py' ! -name 'test_*' | wc -l | tr -d ' ')"
rows="$(printf '%s\n' "$out" | grep -c '  collector ')"
assert_eq "one row per collector adapter" "$adapters" "$rows"
assert_contains "the bundled counter probes as present" "$out" "PASS  collector line-counter"
assert_contains "python row" "$out" "PASS  python"

# 2. A team file written by setup-apply.py in a git repo: parses, untracked
#    until committed (WARN), tracked after the commit (PASS); the resolved
#    reference names the team layer.
(cd "$repo" && git init -q -b main && git config user.email t@example.com && git config user.name t)
python3 "$SCRIPT_DIR/setup-apply.py" --dir "$repo" size.file_lines=500 >/dev/null
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "team layer parses" "$out" "PASS  layer team +$repo/.claude/code-metrics.yaml parses"
assert_row "untracked team file warns" "$out" "WARN  layer team tracked +written but untracked"
assert_row "reference from the team layer" "$out" "reference file_lines +500 \(layer: team\)"
(cd "$repo" && git add .claude && git commit -q -m config)
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
assert_row "committed team file passes" "$out" "PASS  layer team tracked +committed"

# 3. An ignored (and therefore uncommittable) team file is a FAIL and the exit
#    code says so; a local overlay that is not ignored warns with the
#    recommended line. git reports an ignore match only for untracked paths,
#    so the file is untracked first.
(cd "$repo" && git rm -q --cached .claude/code-metrics.yaml && git commit -q -m untrack)
printf '.claude/code-metrics.yaml\n' >"$repo/.gitignore"
printf 'size:\n  file_lines: 7\n' >"$repo/.claude/code-metrics.local.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
rc=$?
assert_eq "ignored team file exits 1" 1 "$rc"
assert_contains "ignored team file fails" "$out" "FAIL  layer team tracked"
assert_contains "unignored overlay warns with the gitignore line" "$out" ".claude/**/*.local.*"
rm -f "$repo/.gitignore"

# 4. A layer outside the subset is a FAIL naming the construct and line.
mkdir -p "$home/.claude"
printf 'lanes:\n  typescript: { enabled: true }\n' >"$home/.claude/code-metrics.yaml"
out="$(bash "$SCRIPT" --repo-root "$repo" --home "$home")"
rc=$?
assert_eq "bad layer exits 1" 1 "$rc"
assert_contains "bad layer names the construct" "$out" "FAIL  layer user-global"
assert_contains "bad layer names the line" "$out" "line 2"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
