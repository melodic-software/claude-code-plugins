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

# A fixture repository carrying the bundled defaults as its team layer, with an empty
# HOME beside it: a root that contains the home is a home root and has no team layer.
new_repo() {
  root="$TEST_TMPDIR/case-$CASES-$RANDOM/repo"
  mkdir -p "$root" "${root%/repo}/home"
  git init -q "$root"
  git -C "$root" config user.email fixture@example.invalid
  git -C "$root" config user.name "Fixture"
  git -C "$root" config commit.gpgsign false
  bash "$APPLY" --defaults --root "$root" >/dev/null
  printf '%s' "$root"
}

check() {
  bash "$SUT" --root "$1" --home "${1%/repo}/home" 2>&1
}

status() {
  bash "$SUT" --root "$1" --home "${1%/repo}/home" >/dev/null 2>&1
  printf '%s' "$?"
}

# shellcheck source=../../../lib/layer-yaml.sh
. "$SCRIPT_DIR/../../../lib/layer-yaml.sh"

TEAM_REL="docs/conventions/docs-naming.yaml"

# set_key <root> <key> <json-value>: rewrite the team YAML with one key replaced.
set_key() {
  doc="$(layer_yaml_to_json "$1/$TEAM_REL" | jq -c --arg k "$2" --argjson v "$3" '.file_names[$k] = $v | .file_names')"
  layer_yaml_render "$doc" >"$1/$TEAM_REL"
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
printf '{oops' >"$root/$TEAM_REL"
out="$(check "$root")"
assert_eq "malformed team layer exits 1" "1" "$(status "$root")"
assert_contains "malformed team layer reports the resolve row" "$out" "FAIL  resolve"
assert_contains "malformed team layer names the YAML file" "$out" "$TEAM_REL"

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

# 5b. A root object with an extension filter and exemptions passes the shape
#     check; one whose extension could not sit in a glob bracket does not.
root="$(new_repo)"
set_key "$root" roots '["docs",{"path":".","extensions":["md"],"exempt_paths":["**/fixtures/**"]}]'
out="$(check "$root")"
assert_contains "a root object passes the shape check" "$out" "PASS  key shape"
set_key "$root" roots '["docs",{"path":".","extensions":["m]d"]}]'
out="$(check "$root")"
assert_contains "a root extension outside letters and digits is refused" "$out" "FAIL  key shape"
for bad in '"../x"' '{"path":"../x"}' '{"path":"/abs"}' '{"path":".","exempt_paths":["docs/../../x"]}'; do
  set_key "$root" roots "[\"docs\",$bad]"
  out="$(check "$root")"
  assert_contains "a root the emitter cannot carry is refused ($bad)" "$out" "must stay inside the repository"
done
# A newline or a non-string extension cannot be written in the YAML subset, which
# reads every scalar as text, so those shapes arrive only from a pre-YAML JSON layer.
root="$(new_repo)"
rm "$root/$TEAM_REL"
mkdir -p "$root/.claude"
printf '{"schema":1,"file_names":{"roots":["docs",{"path":".","extensions":[5]}]}}\n' >"$root/.claude/docs-naming.json"
assert_contains "a non-string root extension is refused" "$(check "$root")" "FAIL  key shape"
printf '{"schema":1,"file_names":{"roots":["docs",{"path":"a\\nb"}]}}\n' >"$root/.claude/docs-naming.json"
assert_contains "a root path with a newline is refused" "$(check "$root")" "must stay inside the repository"

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
printf '%s\n' "$TEAM_REL" >"$root/.gitignore"
out="$(check "$root")"
assert_eq "a gitignored team layer exits 1" "1" "$(status "$root")"
assert_contains "a gitignored team layer is named" "$out" "FAIL  team layer tracked"

# 11. An overlay that is not gitignored warns but does not fail.
root="$(new_repo)"
printf '# nothing of my own yet\n' >"$root/docs/conventions/docs-naming.local.yaml"
out="$(check "$root")"
assert_eq "an un-ignored overlay does not fail the run" "0" "$(status "$root")"
assert_contains "an un-ignored overlay warns with the recommended line" "$out" "WARN  overlay ignored"
assert_contains "the recommended line sits beside the overlay" "$out" "docs/conventions/*.local.*"

# 12. An overlay declaring a team-only key is reported as overridden.
root="$(new_repo)"
printf 'generated:\n  - path: "x"\n    regenerate: "true"\n' >"$root/docs/conventions/docs-naming.local.yaml"
out="$(check "$root")"
assert_contains "a team-only key declared personally is reported" "$out" "WARN  generated override"

# 13. A rule this version does not implement fails.
root="$(new_repo)"
set_key "$root" rule '"SCREAMING_SNAKE"'
assert_contains "an unimplemented rule is refused" "$(check "$root")" "FAIL  rule"

# 13b. A team layer still at the retired docs-hygiene name is read and named.
root="$(new_repo)"
rm "$root/$TEAM_REL"
mkdir -p "$root/.claude"
printf '{"schema": 1, "file_names": {"rule": "lower-kebab"}}\n' >"$root/.claude/docs-hygiene.json"
out="$(check "$root")"
assert_contains "a retired-name team layer is named" "$out" "WARN  layer team"
assert_contains "the retired-name row says which file" "$out" "$root/.claude/docs-hygiene.json is the retired docs-hygiene name"
assert_contains "the resolve row still passes" "$out" "PASS  resolve"
assert_contains "the retired-name row points at the YAML" "$out" "move its settings to the docs-naming YAML"
assert_contains "the tracked row points at apply, which seeds the YAML" "$out" "run setup apply to seed the docs-naming YAML from it"

# 13c. A team layer still in the pre-YAML JSON file is read and named as such; the
#      YAML wins over it once both exist.
root="$(new_repo)"
rm "$root/$TEAM_REL"
mkdir -p "$root/.claude"
printf '{"schema": 1, "file_names": {"rule": "lower-kebab"}}\n' >"$root/.claude/docs-naming.json"
out="$(check "$root")"
assert_eq "a pre-YAML team layer still passes" "0" "$(status "$root")"
assert_contains "the pre-YAML location is warned about" "$out" "WARN  layer team"
assert_contains "the row says it is the pre-YAML location" "$out" "$root/.claude/docs-naming.json is the pre-YAML location"
bash "$APPLY" --defaults --root "$root" >/dev/null
out="$(check "$root")"
assert_contains "once the YAML exists it is the team layer" "$out" "PASS  layer team"
assert_contains "and the team layer is the YAML" "$out" "$root/$TEAM_REL"

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
