#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PLUGIN_OPTION_FILE_NAMES
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/setup-check.sh"
APPLY="$SCRIPT_DIR/setup-apply.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

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

set_key() {
  doc="$(layer_yaml_to_json "$1/$TEAM_REL" | jq -c --arg k "$2" --argjson v "$3" '.file_names[$k] = $v | .file_names')"
  layer_yaml_render "$doc" >"$1/$TEAM_REL"
}

root="$(new_repo)"
out="$(check "$root")"
assert_eq "bundled defaults pass" "0" "$(status "$root")"
assert_contains "bundled defaults: the resolve row passes" "$out" "PASS  resolve"
assert_contains "bundled defaults: the tier forms row passes" "$out" "PASS  tier forms"
assert_contains "bundled defaults: the untracked team layer warns" "$out" "WARN  team layer tracked"

root="$(new_repo)"
printf '{oops' >"$root/$TEAM_REL"
out="$(check "$root")"
assert_eq "malformed team layer exits 1" "1" "$(status "$root")"
assert_contains "malformed team layer reports the resolve row" "$out" "FAIL  resolve"
assert_contains "malformed team layer names the YAML file" "$out" "$TEAM_REL"

root="$(new_repo)"
set_key "$root" regex '"[unclosed"'
out="$(check "$root")"
assert_eq "uncompilable regex exits 1" "1" "$(status "$root")"
assert_contains "uncompilable regex is named" "$out" "FAIL  regex "

root="$(new_repo)"
set_key "$root" regex '"^[a'"'"'z]+$"'
out="$(check "$root")"
assert_contains "a single-quoted regex is refused" "$out" "FAIL  regex quoting"

root="$(new_repo)"
set_key "$root" tiers '[{"name":"a","paths":["x/**"],"forms":"all"},{"name":"a","paths":["y/**"],"forms":"none"}]'
out="$(check "$root")"
assert_eq "duplicate tier names exit 1" "1" "$(status "$root")"
assert_contains "duplicate tier names are listed" "$out" "FAIL  tier names"

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
root="$(new_repo)"
user_layer="${root%/repo}/home/.claude/docs-naming.json"
mkdir -p "${user_layer%/*}"
printf '{"schema":1,"file_names":{"roots":["docs",{"path":".","extensions":[5]}]}}\n' >"$user_layer"
assert_contains "a non-string root extension is refused" "$(check "$root")" "FAIL  key shape"
printf '{"schema":1,"file_names":{"roots":["docs",{"path":"a\\nb"}]}}\n' >"$user_layer"
assert_contains "a root path with a newline is refused" "$(check "$root")" "must stay inside the repository"

root="$(new_repo)"
set_key "$root" tiers '[{"name":"a","paths":["x/**"],"forms":"sometimes"}]'
out="$(check "$root")"
assert_contains "an unknown tier form is refused" "$out" "FAIL  tier forms"

root="$(new_repo)"
set_key "$root" generated '[{"path":"build/out.json","regenerate":"definitely-not-installed --write"}]'
out="$(check "$root")"
assert_eq "an unresolvable regenerator exits 1" "1" "$(status "$root")"
assert_contains "an unresolvable regenerator is named" "$out" "FAIL  generated build/out.json"

root="$(new_repo)"
set_key "$root" generated '[{"path":"build/out.json","regenerate":"bash tools/absent.sh"}]'
out="$(check "$root")"
assert_contains "the script behind bash is the thing resolved" "$out" "regenerator 'tools/absent.sh' resolves to nothing"
mkdir -p "$root/tools" && printf '#!/usr/bin/env bash\n' >"$root/tools/absent.sh"
out="$(check "$root")"
assert_contains "an existing script under the root resolves" "$out" "PASS  generated build/out.json"

root="$(new_repo)"
set_key "$root" generated '[{"path":"build/out.json","regenerate":""}]'
assert_contains "an empty regenerator is refused" "$(check "$root")" "no regenerate command"

root="$(new_repo)"
printf '%s\n' "$TEAM_REL" >"$root/.gitignore"
out="$(check "$root")"
assert_eq "a gitignored team layer exits 1" "1" "$(status "$root")"
assert_contains "a gitignored team layer is named" "$out" "FAIL  team layer tracked"

root="$(new_repo)"
printf '# nothing of my own yet\n' >"$root/docs/conventions/docs-naming.local.yaml"
out="$(check "$root")"
assert_eq "an un-ignored personal override does not fail the run" "0" "$(status "$root")"
assert_contains "an un-ignored personal override warns with the recommended line" "$out" "WARN  personal override ignored"
assert_contains "the recommended line sits beside the personal override" "$out" "docs/conventions/*.local.*"

root="$(new_repo)"
printf 'generated:\n  - path: "x"\n    regenerate: "true"\n' >"$root/docs/conventions/docs-naming.local.yaml"
out="$(check "$root")"
assert_contains "a team-only key declared personally is reported" "$out" "WARN  generated override"

root="$(new_repo)"
set_key "$root" rule '"SCREAMING_SNAKE"'
assert_contains "an unimplemented rule is refused" "$(check "$root")" "FAIL  rule"

root="$(new_repo)"
rm "$root/$TEAM_REL"
mkdir -p "$root/.claude"
printf '{"schema": 1, "file_names": {"rule": "lower-kebab"}}\n' >"$root/.claude/docs-naming.json"
printf '{"schema": 1, "file_names": {"rule": "lower-kebab"}}\n' >"$root/.claude/docs-hygiene.json"
out="$(check "$root")"
assert_eq "an old team file does not fail the run" "0" "$(status "$root")"
assert_contains "the team layer is reported absent" "$out" "INFO  layer team"
assert_contains "the old team file is a WARN row" "$out" "WARN  old team file"
assert_contains "the old team file is named, and apply seeds from it" "$out" "$root/.claude/docs-naming.json is no longer read; /docs-naming:setup apply copies its keys into $root/$TEAM_REL, then delete it"
assert_contains "apply seeds from one file only, so the other is a manual copy" "$out" "$root/.claude/docs-hygiene.json is no longer read; copy any key still wanted into $root/$TEAM_REL by hand, then delete it"

root="$(new_repo)"
mkdir -p "$root/.claude"
printf '{"schema": 1, "file_names": {"rule": "lower-kebab"}}\n' >"$root/.claude/docs-hygiene.json"
out="$(check "$root")"
assert_contains "the YAML stays the team layer" "$out" "PASS  layer team"
assert_contains "the retired-name team file is a manual copy" "$out" "$root/.claude/docs-hygiene.json is no longer read; copy any key still wanted into $root/$TEAM_REL by hand, then delete it"

root="$(new_repo)"
mkdir -p "$root/.claude"
printf '{"schema": 1, "file_names": {}}\n' >"$root/.claude/docs-naming.local.json"
printf '{"schema": 1, "file_names": {}}\n' >"$root/.claude/docs-hygiene.local.json"
out="$(check "$root")"
assert_contains "the old personal override file is a WARN row" "$out" "WARN  old personal override file"
assert_contains "the old personal override is named" "$out" "$root/.claude/docs-naming.local.json is no longer read; move its keys to $root/docs/conventions/docs-naming.local.yaml by hand, then delete it"
assert_contains "the retired-name personal override is named" "$out" "$root/.claude/docs-hygiene.local.json is no longer read; move its keys to"

root="$(new_repo)"
assert_eq "no old file: no old-file row" "0" "$(check "$root" | grep -c 'old .* file')"

root="$(new_repo)"
mkdir -p "${root%/repo}/home/.claude"
printf '{"schema": 1, "file_names": {"rule": "lower-kebab"}}\n' >"${root%/repo}/home/.claude/docs-hygiene.json"
out="$(check "$root")"
assert_contains "the old user file warns" "$out" "WARN  old user file"
assert_contains "and says it is read and apply previews the copy" "$out" "${root%/repo}/home/.claude/docs-hygiene.json is read in place of the file_names option; /docs-naming:setup apply previews copying its keys into the option"
assert_contains "the unset option is an INFO row" "$out" "INFO  layer userConfig"
assert_eq "an old user file does not fail the run" "0" "$(status "$root")"
out="$(bash "$SUT" --root "$root" --home "${root%/repo}/home" --user-config '{"rule": "lower-kebab"}' 2>&1)"
assert_contains "a set option passes" "$out" "PASS  layer userConfig"
assert_contains "with the option set, the old user file is reported unread" "$out" "${root%/repo}/home/.claude/docs-hygiene.json is not read; /docs-naming:setup apply previews copying any key the file_names option lacks into it"
out="$(bash "$SUT" --root "$root" --home "${root%/repo}/home" --user-config '{not json' 2>&1)"
assert_contains "an option that is not one JSON object warns" "$out" "WARN  layer userConfig"
assert_contains "and the run still resolves" "$out" "PASS  resolve"

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
