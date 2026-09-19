#!/usr/bin/env bash
# Self-contained tests for setup-apply.sh. No repository test library: this
# script ships inside the plugin, so its suite has to run wherever the plugin is
# installed.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/setup-apply.sh"
TEMPLATE="$SCRIPT_DIR/../templates/docs-hygiene.json"
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

new_repo() {
  root="$TEST_TMPDIR/repo-$CASES-$RANDOM"
  mkdir -p "$root"
  git init -q "$root"
  git -C "$root" config user.email fixture@example.invalid
  git -C "$root" config user.name "Fixture"
  git -C "$root" config commit.gpgsign false
  printf '%s' "$root"
}

target() { printf '%s/.claude/docs-hygiene.json' "$1"; }

# 1. --defaults writes the bundled document.
root="$(new_repo)"
out="$(bash "$SUT" --defaults --root "$root")"
assert_contains "--defaults reports the path it wrote" "$out" "wrote: .claude/docs-hygiene.json"
assert_contains "--defaults says the file still needs committing" "$out" "commit it"
assert_eq "--defaults writes this contract's schema" "1" "$(jq -r '.schema' "$(target "$root")")"
assert_eq "--defaults carries the bundled roots" "docs" "$(jq -r '.file_names.roots[0]' "$(target "$root")")"
assert_eq "--defaults carries the bundled comment" "true" "$(jq -r 'has("_comment")' "$(target "$root")")"

# 2. A second run changes nothing, bytes included.
before="$(cat "$(target "$root")")"
out="$(bash "$SUT" --defaults --root "$root")"
assert_contains "a no-op re-run says so" "$out" "already configured"
assert_eq "a no-op re-run leaves the bytes alone" "$before" "$(cat "$(target "$root")")"

# 3. A JSON value sets a list.
root="$(new_repo)"
bash "$SUT" --defaults --root "$root" >/dev/null
bash "$SUT" --root "$root" 'roots=["docs","guide"]' >/dev/null
assert_eq "a JSON value sets a list" "docs guide" "$(jq -r '.file_names.roots | join(" ")' "$(target "$root")")"

# 4. A bare value sets a string.
bash "$SUT" --root "$root" 'rule=lower-kebab' >/dev/null
assert_eq "a bare value sets a string" "lower-kebab" "$(jq -r '.file_names.rule' "$(target "$root")")"

# 5. The `file_names.` prefix is optional.
bash "$SUT" --root "$root" 'file_names.regex=^prefixed$' >/dev/null
assert_eq "the file_names prefix is accepted" '^prefixed$' "$(jq -r '.file_names.regex' "$(target "$root")")"

# 6. A value carrying spaces survives, which is what a regenerator command is.
bash "$SUT" --root "$root" 'generated=[{"path":"a.json","regenerate":"bash tools/gen.sh --write a.json"}]' >/dev/null
assert_eq "a spaced regenerator command survives" "bash tools/gen.sh --write a.json" "$(jq -r '.file_names.generated[0].regenerate' "$(target "$root")")"

# 7. Hand-written comment text survives a merge.
assert_eq "the hand-written comment survives every merge" "true" "$(jq -r 'has("_comment")' "$(target "$root")")"

# 8. Nothing outside the one file is written: not .gitignore, not anything else.
root="$(new_repo)"
printf 'node_modules/\n' >"$root/.gitignore"
gitignore_before="$(cat "$root/.gitignore")"
git -C "$root" add -A >/dev/null 2>&1
git -C "$root" commit -qm seed >/dev/null 2>&1
bash "$SUT" --defaults --root "$root" >/dev/null
bash "$SUT" --root "$root" 'roots=["d"]' >/dev/null
assert_eq "the consumer's .gitignore is untouched" "$gitignore_before" "$(cat "$root/.gitignore")"
assert_eq "exactly one path appears in the working tree" "?? .claude/" "$(git -C "$root" status --porcelain)"

# 9. The temp file never survives the run.
assert_eq "no temp file is left behind" "" "$(find "$root/.claude" -name 'docs-hygiene.json.tmp.*' 2>/dev/null)"

# 10. Usage.
assert_eq "no arguments exits 2" "2" "$(
  bash "$SUT" --root "$TEST_TMPDIR" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "an unknown flag exits 2" "2" "$(
  bash "$SUT" --frobnicate --root "$TEST_TMPDIR" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "a bare word that is not a pair exits 2" "2" "$(
  bash "$SUT" nonsense --root "$TEST_TMPDIR" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "--help exits 0" "0" "$(
  bash "$SUT" --help >/dev/null 2>&1
  printf '%s' "$?"
)"

# 11. An existing team layer that does not parse is refused rather than replaced.
root="$(new_repo)"
mkdir -p "$root/.claude"
printf '{broken' >"$(target "$root")"
assert_eq "a malformed existing layer exits 2" "2" "$(
  bash "$SUT" --defaults --root "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "a malformed existing layer is left as it was" "{broken" "$(cat "$(target "$root")")"

# 12. The bundled template itself is valid and carries every documented key.
missing="$(jq -r '
  ["roots","rule","regex","exempt_basenames","exempt_paths","exempt_extensions",
   "tiers","sweep_exclude","sweep_exclude_sites","generated","redirect_map"]
  - (.file_names | keys) | join(" ")
' "$TEMPLATE")"
assert_eq "the bundled template declares every key of the contract" "" "$missing"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
