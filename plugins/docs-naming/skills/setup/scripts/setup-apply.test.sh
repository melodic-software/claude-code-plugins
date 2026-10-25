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
TEMPLATE="$SCRIPT_DIR/../templates/docs-naming.json"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# shellcheck source=../../../lib/layer-yaml.sh
. "$SCRIPT_DIR/../../../lib/layer-yaml.sh"

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

TARGET_REL="docs/conventions/docs-naming.yaml"
target() { printf '%s/%s' "$1" "$TARGET_REL"; }
# The written team layer, as the resolver reads it.
doc() { layer_yaml_to_json "$(target "$1")"; }

# 1. --defaults writes the bundled document as YAML under the convention home.
root="$(new_repo)"
out="$(bash "$SUT" --defaults --root "$root")"
assert_contains "--defaults reports the path it wrote" "$out" "wrote: $TARGET_REL"
assert_contains "--defaults says the file still needs committing" "$out" "commit it"
assert_eq "--defaults carries the bundled roots" "docs" "$(doc "$root" | jq -r '.file_names.roots[0]')"
assert_eq "--defaults carries the bundled regex" "$(jq -r '.file_names.regex' "$TEMPLATE")" "$(doc "$root" | jq -r '.file_names.regex')"
assert_eq "--defaults carries every bundled value" "$(jq -S -c '.file_names' "$TEMPLATE")" "$(doc "$root" | jq -S -c '.file_names')"
assert_eq "--defaults writes no schema or file_names wrapper" "0" "$(grep -c -E '^(schema|file_names):' "$(target "$root")")"
assert_eq "--defaults keeps redirect_map null" "null" "$(doc "$root" | jq -c '.file_names.redirect_map')"
assert_contains "--defaults writes a comment header" "$(head -n 1 "$(target "$root")")" "# docs-naming team layer"

# 2. A second run changes nothing, bytes included.
before="$(cat "$(target "$root")")"
out="$(bash "$SUT" --defaults --root "$root")"
assert_contains "a no-op re-run says so" "$out" "already configured"
assert_eq "a no-op re-run leaves the bytes alone" "$before" "$(cat "$(target "$root")")"

# 3. A JSON value sets a list.
root="$(new_repo)"
bash "$SUT" --defaults --root "$root" >/dev/null
bash "$SUT" --root "$root" 'roots=["docs","guide"]' >/dev/null
assert_eq "a JSON value sets a list" "docs guide" "$(doc "$root" | jq -r '.file_names.roots | join(" ")')"

# 4. A bare value sets a string.
bash "$SUT" --root "$root" 'rule=lower-kebab' >/dev/null
assert_eq "a bare value sets a string" "lower-kebab" "$(doc "$root" | jq -r '.file_names.rule')"

# 5. The `file_names.` prefix is optional.
bash "$SUT" --root "$root" 'file_names.regex=^prefixed$' >/dev/null
assert_eq "the file_names prefix is accepted" '^prefixed$' "$(doc "$root" | jq -r '.file_names.regex')"

# 6. A value carrying spaces and quotes survives, which is what a regenerator command is.
bash "$SUT" --root "$root" 'generated=[{"path":"a.json","regenerate":"bash tools/gen.sh --write '"'"'a b'"'"' a.json"}]' >/dev/null
assert_eq "a spaced regenerator command survives" "bash tools/gen.sh --write 'a b' a.json" "$(doc "$root" | jq -r '.file_names.generated[0].regenerate')"
bash "$SUT" --root "$root" 'roots=[{"path":".","extensions":["md"],"exempt_paths":["**/fixtures/**"]}]' >/dev/null
assert_eq "a root object survives" '[{"path":".","extensions":["md"],"exempt_paths":["**/fixtures/**"]}]' "$(doc "$root" | jq -c '.file_names.roots')"
bash "$SUT" --root "$root" 'exempt_paths=[]' >/dev/null
assert_eq "an explicit empty list stays declared" "[]" "$(doc "$root" | jq -c '.file_names.exempt_paths')"

# 7. The hand-written comment header survives a merge.
root="$(new_repo)"
bash "$SUT" --defaults --root "$root" >/dev/null
{
  printf '# hand-written: why these roots\n'
  tail -n +2 "$(target "$root")"
} >"$TEST_TMPDIR/edited.yaml"
cp "$TEST_TMPDIR/edited.yaml" "$(target "$root")"
bash "$SUT" --root "$root" 'roots=["d"]' >/dev/null
assert_eq "the hand-written header survives every merge" "# hand-written: why these roots" "$(head -n 1 "$(target "$root")")"

# 8. Nothing outside the one file is written: not .gitignore, not anything else.
root="$(new_repo)"
printf 'node_modules/\n' >"$root/.gitignore"
gitignore_before="$(cat "$root/.gitignore")"
git -C "$root" add -A >/dev/null 2>&1
git -C "$root" commit -qm seed >/dev/null 2>&1
bash "$SUT" --defaults --root "$root" >/dev/null
bash "$SUT" --root "$root" 'roots=["d"]' >/dev/null
assert_eq "the consumer's .gitignore is untouched" "$gitignore_before" "$(cat "$root/.gitignore")"
assert_eq "exactly one path appears in the working tree" "?? docs/" "$(git -C "$root" status --porcelain)"
assert_eq "and it is the one team file" "$TARGET_REL" "$(git -C "$root" status --porcelain -uall | sed 's/^?? //')"

# 9. The temp file never survives the run.
assert_eq "no temp file is left behind" "" "$(find "$root/docs" -name 'docs-naming.yaml.tmp.*' 2>/dev/null)"

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
mkdir -p "$root/docs/conventions"
printf '{broken' >"$(target "$root")"
assert_eq "a malformed existing layer exits 2" "2" "$(
  bash "$SUT" --defaults --root "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "a malformed existing layer is left as it was" "{broken" "$(cat "$(target "$root")")"

# 11b. A team layer still at the retired docs-hygiene name is migrated, never
#      shadowed by a fresh docs-naming.yaml.
root="$(new_repo)"
mkdir -p "$root/.claude"
printf '{"schema": 1, "file_names": {"rule": "lower-kebab", "regex": "^retired$"}}\n' >"$root/.claude/docs-hygiene.json"
out="$(bash "$SUT" --defaults --root "$root")"
assert_contains "the retired-name migration names the file it read" "$out" "migrated: $TARGET_REL now supplies the team layer; .claude/docs-hygiene.json is ignored"
assert_eq "the retired-name regex carried over" "^retired$" "$(doc "$root" | jq -r '.file_names.regex')"
assert_eq "the retired-name file is left alone" "^retired$" "$(jq -r '.file_names.regex' "$root/.claude/docs-hygiene.json")"

# 11c. The pre-YAML JSON team layer is migrated, not shadowed: the first write
#      seeds the YAML from it and leaves the JSON where it was.
root="$(new_repo)"
mkdir -p "$root/.claude"
printf '{"schema": 1, "_comment": "why we differ", "file_names": {"rule": "lower-kebab", "regex": "^old$", "roots": ["docs", "guide"]}}\n' >"$root/.claude/docs-naming.json"
out="$(bash "$SUT" --root "$root" 'exempt_paths=["docs/x/**"]')"
assert_contains "the migration is reported" "$out" "migrated: $TARGET_REL"
assert_eq "the old regex carried over" "^old$" "$(doc "$root" | jq -r '.file_names.regex')"
assert_eq "the old roots carried over" "docs guide" "$(doc "$root" | jq -r '.file_names.roots | join(" ")')"
assert_eq "the new key is merged in" "docs/x/**" "$(doc "$root" | jq -r '.file_names.exempt_paths[0]')"
assert_contains "the old comment became the header" "$(head -n 3 "$(target "$root")")" "# why we differ"
assert_eq "the old file is left alone" "^old$" "$(jq -r '.file_names.regex' "$root/.claude/docs-naming.json")"
mkdir -p "$TEST_TMPDIR/nohome"
assert_eq "the resolver now reads the YAML" "^old$" "$(bash "$SCRIPT_DIR/../../../scripts/resolve-config.sh" resolve --root "$root" --home "$TEST_TMPDIR/nohome" 2>/dev/null | jq -r '.file_names.regex')"

# 12. The bundled template itself is valid and carries every documented key.
missing="$(jq -r '
  ["roots","rule","regex","exempt_basenames","exempt_paths","exempt_extensions",
   "tiers","sweep_exclude","sweep_exclude_sites","generated","redirect_map"]
  - (.file_names | keys) | join(" ")
' "$TEMPLATE")"
assert_eq "the bundled template declares every key of the contract" "" "$missing"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
