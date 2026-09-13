#!/usr/bin/env bash
# Self-contained tests for setup-check.sh. No repository test library: this
# script ships inside the plugin, so its suite has to run wherever the plugin is
# installed.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/setup-check.sh"
APPLY="$SCRIPT_DIR/setup-apply.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0

pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

# A fixture repository carrying the bundled defaults as its team layer.
new_repo() {
  root="$TEST_TMPDIR/repo-$CASES-$RANDOM"
  mkdir -p "$root/home"
  git init -q "$root"
  git -C "$root" config user.email fixture@example.invalid
  git -C "$root" config user.name "Fixture"
  git -C "$root" config commit.gpgsign false
  bash "$APPLY" --defaults --root "$root" >/dev/null
  printf '%s' "$root"
}

check() {
  bash "$SUT" --root "$1" --home "$1/home" 2>&1
}

status() {
  bash "$SUT" --root "$1" --home "$1/home" >/dev/null 2>&1
  printf '%s' "$?"
}

# set_key <root> <key> <json-value>
set_key() {
  tmp="$1/.claude/t.json"
  jq --arg k "$2" --argjson v "$3" '.file_names[$k] = $v' "$1/.claude/docs-hygiene.json" >"$tmp"
  mv "$tmp" "$1/.claude/docs-hygiene.json"
}

# 1. A repository carrying the bundled defaults passes.
root="$(new_repo)"
out="$(check "$root")"
assert_eq "bundled defaults pass" "0" "$(status "$root")"
assert_contains "bundled defaults: the resolve row passes" "$out" "PASS  resolve"
assert_contains "bundled defaults: the tier forms row passes" "$out" "PASS  tier forms"
assert_contains "bundled defaults: the untracked team layer warns" "$out" "WARN  team layer tracked"

# 2. A team layer that does not parse fails, naming the resolve row.
root="$(new_repo)"
printf '{oops' >"$root/.claude/docs-hygiene.json"
out="$(check "$root")"
assert_eq "malformed team layer exits 1" "1" "$(status "$root")"
assert_contains "malformed team layer reports the resolve row" "$out" "FAIL  resolve"

# 3. A regex grep cannot compile fails.
root="$(new_repo)"
set_key "$root" regex '"[unclosed"'
out="$(check "$root")"
assert_eq "uncompilable regex exits 1" "1" "$(status "$root")"
assert_contains "uncompilable regex is named" "$out" "FAIL  regex "

# 4. A regex carrying a single quote fails: the gate emitter inlines the value.
root="$(new_repo)"
set_key "$root" regex '"^[a'"'"'z]+$"'
out="$(check "$root")"
assert_contains "a single-quoted regex is refused" "$out" "FAIL  regex quoting"

# 5. Duplicate tier names fail.
root="$(new_repo)"
set_key "$root" tiers '[{"name":"a","paths":["x/**"],"forms":"all"},{"name":"a","paths":["y/**"],"forms":"none"}]'
out="$(check "$root")"
assert_eq "duplicate tier names exit 1" "1" "$(status "$root")"
assert_contains "duplicate tier names are listed" "$out" "FAIL  tier names"

# 6. An unknown tier form fails.
root="$(new_repo)"
set_key "$root" tiers '[{"name":"a","paths":["x/**"],"forms":"sometimes"}]'
out="$(check "$root")"
assert_contains "an unknown tier form is refused" "$out" "FAIL  tier forms"

# 7. A regenerator whose command resolves to nothing fails.
root="$(new_repo)"
set_key "$root" generated '[{"path":"build/out.json","regenerate":"definitely-not-installed --write"}]'
out="$(check "$root")"
assert_eq "an unresolvable regenerator exits 1" "1" "$(status "$root")"
assert_contains "an unresolvable regenerator is named" "$out" "FAIL  generated build/out.json"

# 8. An interpreter-led regenerator is resolved past the interpreter.
root="$(new_repo)"
set_key "$root" generated '[{"path":"build/out.json","regenerate":"bash tools/absent.sh"}]'
out="$(check "$root")"
assert_contains "the script behind bash is the thing resolved" "$out" "regenerator 'tools/absent.sh' resolves to nothing"
mkdir -p "$root/tools" && printf '#!/usr/bin/env bash\n' >"$root/tools/absent.sh"
out="$(check "$root")"
assert_contains "an existing script under the root resolves" "$out" "PASS  generated build/out.json"

# 9. A regenerator with no command at all fails.
root="$(new_repo)"
set_key "$root" generated '[{"path":"build/out.json","regenerate":""}]'
assert_contains "an empty regenerator is refused" "$(check "$root")" "no regenerate command"

# 10. A gitignored team layer fails: it never reaches the team.
root="$(new_repo)"
printf '.claude/docs-hygiene.json\n' >"$root/.gitignore"
out="$(check "$root")"
assert_eq "a gitignored team layer exits 1" "1" "$(status "$root")"
assert_contains "a gitignored team layer is named" "$out" "FAIL  team layer tracked"

# 11. An overlay that is not gitignored warns but does not fail.
root="$(new_repo)"
printf '{"schema":1,"file_names":{}}\n' >"$root/.claude/docs-hygiene.local.json"
out="$(check "$root")"
assert_eq "an un-ignored overlay does not fail the run" "0" "$(status "$root")"
assert_contains "an un-ignored overlay warns with the recommended line" "$out" "WARN  overlay ignored"

# 12. An overlay declaring a team-only key is reported as overridden.
root="$(new_repo)"
printf '{"schema":1,"file_names":{"generated":[{"path":"x","regenerate":"true"}]}}\n' >"$root/.claude/docs-hygiene.local.json"
out="$(check "$root")"
assert_contains "a team-only key declared personally is reported" "$out" "WARN  generated override"

# 13. A rule this version does not implement fails.
root="$(new_repo)"
set_key "$root" rule '"SCREAMING_SNAKE"'
assert_contains "an unimplemented rule is refused" "$(check "$root")" "FAIL  rule"

# 14. Usage.
assert_eq "--help exits 0" "0" "$(
  bash "$SUT" --help >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "an unknown argument exits 2" "2" "$(
  bash "$SUT" --frobnicate >/dev/null 2>&1
  printf '%s' "$?"
)"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
