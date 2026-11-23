#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PLUGIN_OPTION_FILE_NAMES
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/resolve-config.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"

home_of() {
  printf '%s' "${1%/repo}/home"
}

new_root() {
  root="$TEST_TMPDIR/case-$CASES-$RANDOM/repo"
  mkdir -p "$root/.claude" "$(home_of "$root")"
  git init -q "$root" >/dev/null 2>&1
  printf '%s' "$root"
}

write_layer() {
  schema="${3:-1}"
  mkdir -p "$(dirname "$1")"
  printf '{"schema": %s, "file_names": %s}\n' "$schema" "$2" >"$1"
}

# shellcheck source=../lib/layer-yaml.sh
. "$SCRIPT_DIR/../lib/layer-yaml.sh"

write_yaml() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}

write_team() {
  write_yaml "$1/docs/conventions/docs-naming.yaml" "$(layer_yaml_render "$2")"
}

write_personal() {
  write_yaml "$1/docs/conventions/docs-naming.local.yaml" "$(layer_yaml_render "$2")"
}

resolve() {
  r="$1"
  shift
  bash "$SUT" resolve --root "$r" --home "$(home_of "$r")" "$@"
}

layers() {
  r="$1"
  shift
  bash "$SUT" layers --root "$r" --home "$(home_of "$r")" "$@"
}

root="$(new_root)"
out="$(resolve "$root")"
assert_eq "no layers: rule is the bundled lower-kebab" "lower-kebab" "$(printf '%s' "$out" | jq -r '.file_names.rule')"
assert_eq "no layers: roots is the bundled docs" "docs" "$(printf '%s' "$out" | jq -r '.file_names.roots[0]')"
assert_eq "no layers: schema is stamped" "1" "$(printf '%s' "$out" | jq -r '.schema')"
assert_eq "no layers: every key is provenance bundled" "" "$(layers "$root" | grep -v 'bundled$' || true)"

root="$(new_root)"
write_team "$root" '{"regex": "^team$"}'
assert_eq "team layer: regex overrides the default" "^team$" "$(resolve "$root" | jq -r '.file_names.regex')"
assert_contains "team layer: provenance names it" "$(layers "$root")" "regex	bundled,team"

write_personal "$root" '{"regex": "^personal$"}'
assert_eq "personal override: nearest wins on regex" "^personal$" "$(resolve "$root" | jq -r '.file_names.regex')"

root="$(new_root)"
write_team "$root" '{"rule": "team-rule", "regex": "^team$"}'
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"rule": "user-rule", "regex": "^user$"}'
assert_eq "team beats the old user file on rule" "team-rule" "$(resolve "$root" 2>/dev/null | jq -r '.file_names.rule')"
assert_eq "team beats the old user file on regex" "^team$" "$(resolve "$root" 2>/dev/null | jq -r '.file_names.regex')"
assert_contains "provenance lists both, team last" "$(layers "$root")" "rule	bundled,userConfig,team"
assert_eq "team beats the userConfig option on rule" "team-rule" "$(resolve "$root" --user-config '{"rule": "option-rule"}' 2>/dev/null | jq -r '.file_names.rule')"

root="$(new_root)"
write_team "$root" '{"sweep_exclude": ["docs/frozen/**"]}'
write_personal "$root" '{"sweep_exclude": ["docs/mine/**"]}'
out="$(resolve "$root" | jq -c '.file_names.sweep_exclude')"
assert_contains "additive: the team entry survives the personal override" "$out" '"docs/frozen/**"'
assert_contains "additive: the personal override's entry is added" "$out" '"docs/mine/**"'
assert_lacks "additive: the team layer replaced the bundled default" "$out" '".work/**"'

root="$(new_root)"
write_personal "$root" '{"sweep_exclude": ["docs/mine/**"]}'
out="$(resolve "$root" | jq -c '.file_names.sweep_exclude')"
assert_contains "additive: the bundled default survives a personal addition" "$out" '".work/**"'
assert_contains "additive: the personal entry is added to it" "$out" '"docs/mine/**"'

root="$(new_root)"
write_personal "$root" '{"tiers": [{"name": "mine", "paths": ["docs/x/**"], "forms": "all"}]}'
names="$(resolve "$root" | jq -r '.file_names.tiers[].name' | sort | tr '\n' ' ')"
assert_eq "policy floor: the personal override adds a tier and removes none" "historical mine released " "$names"

root="$(new_root)"
write_personal "$root" '{"generated": [{"path": "x", "regenerate": "rm -rf /"}]}'
out="$(resolve "$root" | jq -c '.file_names.generated')"
assert_eq "team-only: the personal override's regenerator is ignored" "[]" "$out"
assert_contains "team-only: the personal override's declaration is reported inert" "$(layers "$root")" "!inert:generated	personal-override"

root="$(new_root)"
assert_eq "team-only: the option's regenerator is ignored" "[]" "$(resolve "$root" --user-config '{"generated": [{"path": "y", "regenerate": "true"}]}' | jq -c '.file_names.generated')"
assert_contains "team-only: the option's declaration is reported inert" "$(layers "$root" --user-config '{"generated": [{"path": "y", "regenerate": "true"}]}')" "!inert:generated	userConfig"
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"generated": [{"path": "y", "regenerate": "true"}]}'
assert_eq "team-only: an old user file's regenerator is ignored" "[]" "$(resolve "$root" 2>/dev/null | jq -c '.file_names.generated')"
assert_contains "team-only: an old user file's declaration is reported inert" "$(layers "$root")" "!inert:generated	userConfig"

root="$(new_root)"
write_team "$root" '{"generated": [{"path": "build/out.json", "regenerate": "make out"}]}'
assert_eq "team layer supplies the regenerator" "build/out.json" "$(resolve "$root" | jq -r '.file_names.generated[0].path')"

root="$(new_root)"
mkdir -p "$(home_of "$root")/.claude"
printf '{not json' >"$(home_of "$root")/.claude/docs-naming.json"
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_eq "malformed old user file exits 2" "2" "$(
  resolve "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_contains "malformed old user file is named" "$err" "$(home_of "$root")/.claude/docs-naming.json"

root="$(new_root)"
printf '{not json' >"$root/.claude/docs-naming.json"
assert_eq "an old team JSON, even malformed, is ignored" "lower-kebab" "$(resolve "$root" 2>/dev/null | jq -r '.file_names.rule')"

root="$(new_root)"
mkdir -p "$(home_of "$root")/.claude"
printf '{"file_names": {"rule": "lower-kebab"}}\n' >"$(home_of "$root")/.claude/docs-naming.json"
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_contains "missing schema is refused" "$err" "schema 'missing'"

root="$(new_root)"
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"rule": "lower-kebab"}' 99
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_contains "unknown schema is refused" "$err" "schema '99'"

root="$(new_root)"
mkdir -p "$root/bin"
{
  printf '#!/usr/bin/env bash\n'
  printf 'REAL=%q\n' "$(command -v jq)"
  # shellcheck disable=SC2016  # the body of the stub script, expanded when it runs, not here
  printf '"$REAL" "$@" | sed "s/$/\\r/"\n'
} >"$root/bin/jq"
chmod +x "$root/bin/jq"
write_team "$root" '{"regex": "^crlf$"}'
out="$(PATH="$root/bin:$PATH" resolve "$root" | jq -r '.file_names.regex')"
assert_eq "CRLF jq: the resolved regex carries no carriage return" "^crlf$" "$out"

assert_eq "unknown action exits 2" "2" "$(
  bash "$SUT" frobnicate >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "no action exits 2" "2" "$(
  bash "$SUT" --root "$TEST_TMPDIR" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "a missing --root directory exits 2" "2" "$(
  bash "$SUT" resolve --root "$TEST_TMPDIR/nope" >/dev/null 2>&1
  printf '%s' "$?"
)"

root="$(new_root)"
write_team "$root" '{"rule": "lower-kebab"}'
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "paths: the team YAML is present" "$out" "team	$root/docs/conventions/docs-naming.yaml	present"
assert_contains "paths: the userConfig option is absent" "$out" "userConfig	file_names	absent"
assert_lacks "paths: no old user file row when none exists" "$out" "legacy"
assert_contains "paths: the personal override is absent, at its YAML path" "$out" "personal-override	$root/docs/conventions/docs-naming.local.yaml	absent"

root="$(new_root)"
git init -q "$root" >/dev/null 2>&1
git -C "$root" config user.email fixture@example.invalid
git -C "$root" config user.name "Fixture"
git -C "$root" config commit.gpgsign false
write_team "$root" '{"regex": "^from-cwd$"}'
jq_bin="$TEST_TMPDIR/jq-bin"
mkdir -p "$jq_bin"
ln -sf "$(mise which jq 2>/dev/null || command -v jq)" "$jq_bin/jq"
out="$(cd "$root" && HOME="$(home_of "$root")" PATH="$jq_bin:$PATH" bash "$SUT" resolve | jq -r '.file_names.regex')"
assert_eq "no --root: the git toplevel of the cwd supplies the team layer" "^from-cwd$" "$out"

root="$(new_root)"
write_team "$root" \
  '{"tiers": [{"name": "t-team", "paths": ["docs/a/**"], "forms": "none"}]}'
write_layer "$(home_of "$root")/.claude/docs-naming.json" \
  '{"tiers": [{"name": "t-personal", "paths": ["docs/a/deep/**"], "forms": "all"}]}'
tiers="$(resolve "$root" | jq -c '.file_names.tiers')"
assert_contains "a team tier is stamped team" "$tiers" '"name":"t-team"'
assert_contains "and carries its layer" "$tiers" '"_layer":"team"'
assert_contains "a personal tier is still appended" "$tiers" '"name":"t-personal"'
assert_contains "and is stamped with the layer that added it" "$tiers" '"_layer":"userConfig"'

home="$TEST_TMPDIR/hroot/home"
mkdir -p "$home/.claude"
write_layer "$home/.claude/docs-naming.json" '{"rule": "home-rule", "generated": [{"path": "y", "regenerate": "true"}]}'
out="$(bash "$SUT" resolve --root "$home" --home "$home")"
assert_eq "home root: the old user file supplies its nearest-wins key" "home-rule" "$(printf '%s' "$out" | jq -r '.file_names.rule')"
assert_eq "home root: a team-only key in the old user file is not read as team" "null" "$(printf '%s' "$out" | jq -c '[.file_names.generated[].path] | index("y")')"
out="$(bash "$SUT" layers --root "$home" --home "$home")"
assert_contains "home root: provenance names the userConfig layer once" "$out" "rule	bundled,userConfig
"
assert_lacks "home root: provenance never names the team layer" "$out" ",team"
out="$(bash "$SUT" paths --root "$home" --home "$home")"
assert_contains "home root: paths marks team not-applicable" "$out" "team	-	not-applicable: home root"
assert_contains "home root: paths marks the personal override not-applicable" "$out" "personal-override	-	not-applicable: home root"

parent="$TEST_TMPDIR/hroot"
write_team "$parent" '{"rule": "ancestor-rule"}'
out="$(bash "$SUT" resolve --root "$parent" --home "$home")"
assert_eq "an ancestor of the home is a home root: its YAML is not the team layer" "home-rule" "$(printf '%s' "$out" | jq -r '.file_names.rule')"

git init -q "$home" >/dev/null 2>&1
out="$(bash "$SUT" paths --root "$home" --home "$home")"
assert_contains "a git repository at the home is still a home root" "$out" "team	-	not-applicable: home root"

plain="$TEST_TMPDIR/plain"
mkdir -p "$TEST_TMPDIR/plainhome"
write_team "$plain" '{"rule": "plain-team"}'
write_personal "$plain" '{"rule": "plain-personal"}'
out="$(bash "$SUT" resolve --root "$plain" --home "$TEST_TMPDIR/plainhome")"
assert_eq "a non-repo root: the bundled rule stands" "lower-kebab" "$(printf '%s' "$out" | jq -r '.file_names.rule')"
out="$(bash "$SUT" paths --root "$plain" --home "$TEST_TMPDIR/plainhome")"
assert_contains "a non-repo root: paths marks team not-applicable" "$out" "team	-	not-applicable: non-repo root"

root="$(new_root)"
write_layer "$(home_of "$root")/.claude/docs-hygiene.json" '{"regex": "^retired$"}'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
err="$(cat "$TEST_TMPDIR/err")"
assert_eq "retired name: the old user file is still read" "^retired$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_contains "retired name: resolve warns and names the file" "$err" "WARN: reading $(home_of "$root")/.claude/docs-hygiene.json from an old location; move its keys into the docs-naming plugin's file_names userConfig option"
assert_eq "retired name: resolve prints one warning" "1" "$(grep -c 'WARN' "$TEST_TMPDIR/err")"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "retired name: paths reports the old user file as legacy" "$out" "userConfig	$(home_of "$root")/.claude/docs-hygiene.json	legacy"
assert_eq "retired name: layers stays quiet on stderr" "" "$(layers "$root" 2>&1 >/dev/null)"
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"regex": "^current$"}'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
assert_eq "retired name: docs-naming.json wins when both old files exist" "^current$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_contains "retired name: the warning names the docs-hygiene file as not read" "$(cat "$TEST_TMPDIR/err")" "and $(home_of "$root")/.claude/docs-hygiene.json is not read while it exists"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "retired name: paths reports docs-naming.json as read" "$out" "userConfig	$(home_of "$root")/.claude/docs-naming.json	legacy"
assert_contains "retired name: paths reports docs-hygiene.json as unread" "$out" "userConfig	$(home_of "$root")/.claude/docs-hygiene.json	legacy-unread"

root="$(new_root)"
out="$(resolve "$root" --user-config '{"regex": "^option$", "exempt_basenames": ["NOTES.md"]}' 2>"$TEST_TMPDIR/err")"
assert_eq "option only: the option supplies a nearest-wins key" "^option$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_contains "option only: the option adds to an additive key" "$(printf '%s' "$out" | jq -c '.file_names.exempt_basenames')" '"NOTES.md"'
assert_contains "option only: the bundled entries stay" "$(printf '%s' "$out" | jq -c '.file_names.exempt_basenames')" '"README.md"'
assert_eq "option only: resolve is quiet on stderr" "" "$(cat "$TEST_TMPDIR/err")"
assert_contains "option only: provenance names userConfig" "$(layers "$root" --user-config '{"regex": "^option$"}')" "regex	bundled,userConfig"
assert_contains "option only: paths reports the option present" "$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")" --user-config '{"regex": "^option$"}')" "userConfig	file_names	present"
out="$(CLAUDE_PLUGIN_OPTION_FILE_NAMES='{"regex": "^from-env$"}' resolve "$root")"
assert_eq "option only: the hook environment variable supplies the option" "^from-env$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
out="$(CLAUDE_PLUGIN_OPTION_FILE_NAMES='{"regex": "^from-env$"}' resolve "$root" --user-config '{"regex": "^from-flag$"}')"
assert_eq "option only: the flag beats the environment variable" "^from-flag$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
for unset_value in '' '   ' "\${user_config.file_names}"; do
  out="$(resolve "$root" --user-config "$unset_value" 2>"$TEST_TMPDIR/err")"
  assert_eq "option unset ($unset_value): the bundled regex stands" "$(jq -r '.file_names.regex' "$SCRIPT_DIR/../skills/setup/templates/docs-naming.json")" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
  assert_eq "option unset ($unset_value): resolve is quiet on stderr" "" "$(cat "$TEST_TMPDIR/err")"
  assert_contains "option unset ($unset_value): paths reports it absent" "$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")" --user-config "$unset_value")" "userConfig	file_names	absent"
done

root="$(new_root)"
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"regex": "^old$", "sweep_exclude": ["docs/old/**"]}'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
assert_eq "old file only: its nearest-wins value applies" "^old$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_contains "old file only: its additive value applies" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')" '"docs/old/**"'
assert_contains "old file only: the warning names the old file" "$(cat "$TEST_TMPDIR/err")" "WARN: reading $(home_of "$root")/.claude/docs-naming.json from an old location"
assert_contains "old file only: the warning names the new location" "$(cat "$TEST_TMPDIR/err")" "file_names userConfig option"
assert_eq "old file only: one warning" "1" "$(grep -c 'WARN' "$TEST_TMPDIR/err")"
out="$(resolve "$root" --user-config '{"regex": "^option$"}' 2>"$TEST_TMPDIR/err")"
assert_eq "both: the option wins" "^option$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_lacks "both: the old file is not merged in" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')" "docs/old/**"
assert_contains "both: the warning names the option" "$(cat "$TEST_TMPDIR/err")" "the docs-naming plugin's file_names userConfig option is set"
assert_contains "both: the warning names the old file" "$(cat "$TEST_TMPDIR/err")" "$(home_of "$root")/.claude/docs-naming.json at an old location is not read"
assert_eq "both: one warning" "1" "$(grep -c 'WARN' "$TEST_TMPDIR/err")"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")" --user-config '{"regex": "^option$"}')"
assert_contains "both: paths reports the option present" "$out" "userConfig	file_names	present"
assert_contains "both: paths reports the old file unread" "$out" "userConfig	$(home_of "$root")/.claude/docs-naming.json	legacy-unread"
out="$(resolve "$root" --user-config '["not", "an object"]' 2>"$TEST_TMPDIR/err")"
assert_eq "invalid option: resolve still exits 0" "0" "$?"
assert_eq "invalid option: the option is ignored and the old file still applies" "^old$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_contains "invalid option: the warning names the option and its value" "$(cat "$TEST_TMPDIR/err")" 'is not one JSON object and is ignored: ["not", "an object"]'
assert_contains "invalid option: the old file is still named" "$(cat "$TEST_TMPDIR/err")" "WARN: reading $(home_of "$root")/.claude/docs-naming.json from an old location"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")" --user-config '{not json')"
assert_contains "invalid option: paths reports it invalid" "$out" "userConfig	file_names	invalid"
assert_contains "invalid option: paths reports the old file read" "$out" "userConfig	$(home_of "$root")/.claude/docs-naming.json	legacy"
out="$(resolve "$root" --user-config '{"schema": 1, "file_names": {"regex": "^pasted$"}}' 2>/dev/null)"
assert_eq "a whole old file pasted into the option is read as its file_names" "^pasted$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
rm "$(home_of "$root")/.claude/docs-naming.json"
out="$(resolve "$root" --user-config '["not", "an object"]' 2>/dev/null)"
assert_eq "invalid option with no old file: the bundled regex stands" "$(jq -r '.file_names.regex' "$SCRIPT_DIR/../skills/setup/templates/docs-naming.json")" "$(printf '%s' "$out" | jq -r '.file_names.regex')"

root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.json" '{"regex": "^retired$"}'
write_layer "$root/.claude/docs-hygiene.local.json" '{"exempt_paths": ["docs/retired/**"]}'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
assert_eq "retired team name: not read" "$(jq -r '.file_names.regex' "$SCRIPT_DIR/../skills/setup/templates/docs-naming.json")" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_lacks "retired personal override name: not read" "$(printf '%s' "$out" | jq -c '.file_names.exempt_paths')" "docs/retired/**"
assert_eq "retired team name: resolve is quiet on stderr" "" "$(cat "$TEST_TMPDIR/err")"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "retired team name: paths reports the team YAML absent" "$out" "team	$root/docs/conventions/docs-naming.yaml	absent"

new_repo() {
  new_root
}

root="$(new_repo)"
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^yaml-team$"'
assert_eq "yaml team layer: regex overrides the default" "^yaml-team$" "$(resolve "$root" | jq -r '.file_names.regex')"
assert_contains "yaml team layer: provenance names the team layer" "$(layers "$root")" "regex	bundled,team"
assert_contains "yaml team layer: a key it does not set stays bundled" "$(layers "$root")" "rule	bundled
"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "yaml team layer: paths names the file and says present" "$out" "team	$root/docs/conventions/docs-naming.yaml	present"
assert_eq "yaml team layer: resolve is quiet on stderr" "" "$(resolve "$root" 2>&1 >/dev/null)"

root="$(new_repo)"
write_layer "$root/.claude/docs-naming.json" '{"regex": "^old$", "sweep_exclude": ["docs/old/**"]}'
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^new$"'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
assert_eq "both exist: the YAML supplies the regex" "^new$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_lacks "both exist: nothing from the JSON is merged in" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')" "docs/old/**"
assert_eq "both exist: no warning, the JSON is not read" "" "$(cat "$TEST_TMPDIR/err")"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "both exist: paths reports the YAML" "$out" "team	$root/docs/conventions/docs-naming.yaml	present"

root="$(new_repo)"
write_layer "$root/.claude/docs-naming.json" '{"regex": "^old$"}'
write_layer "$root/.claude/docs-naming.local.json" '{"sweep_exclude": ["docs/mine/**"]}'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
assert_eq "no YAML: the old team JSON is not read" "$(jq -r '.file_names.regex' "$SCRIPT_DIR/../skills/setup/templates/docs-naming.json")" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_lacks "no YAML: the old personal override JSON is not read" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')" "docs/mine/**"
assert_eq "no YAML: resolve stays quiet on stderr, which skill scripts pass through" "" "$(cat "$TEST_TMPDIR/err")"
pout="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "no YAML: paths reports the team YAML absent" "$pout" "team	$root/docs/conventions/docs-naming.yaml	absent"
assert_contains "no YAML: paths reports the personal override YAML absent" "$pout" "personal-override	$root/docs/conventions/docs-naming.local.yaml	absent"
assert_eq "no YAML: every key stays bundled" "" "$(layers "$root" | grep -v 'bundled$' || true)"

root="$(new_repo)"
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"rule": "user-rule", "regex": "^user$", "exempt_extensions": ["rb"]}'
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^team$"
exempt_basenames:
  - "TEAM.md"'
write_yaml "$root/docs/conventions/docs-naming.local.yaml" 'exempt_basenames:
  - "MINE.md"'
lay="$(layers "$root")"
assert_contains "provenance: a nearest-wins key lists userConfig then team" "$lay" "regex	bundled,userConfig,team"
assert_contains "provenance: the userConfig rule survives where the team sets none" "$lay" "rule	bundled,userConfig"
assert_contains "provenance: an additive key lists team then the personal override" "$lay" "exempt_basenames	bundled,team,personal-override"
assert_contains "provenance: an additive key the userConfig layer sets" "$lay" "exempt_extensions	bundled,userConfig"
assert_eq "provenance: the team basenames replace the default, the personal override adds" "TEAM.md MINE.md" "$(resolve "$root" 2>/dev/null | jq -r '.file_names.exempt_basenames | join(" ")')"

root="$(new_repo)"
write_yaml "$root/docs/conventions/docs-naming.yaml" 'roots:
  - "docs"
  - path: "."
    extensions:
      - "md"
    exempt_paths:
      - "**/fixtures/**"
sweep_exclude: []
tiers:
  - name: "frozen"
    paths:
      - "docs/adr/**"
    forms: "none"
generated:
  - path: "out.json"
    regenerate: "bash gen.sh --flag '"'"'a b'"'"' > out.json"
    churn:
      - "generated_on"
redirect_map: null'
out="$(resolve "$root")"
assert_eq "yaml: a root object keeps its fields" '{"path":".","extensions":["md"],"exempt_paths":["**/fixtures/**"]}' "$(printf '%s' "$out" | jq -c '.file_names.roots[1]')"
assert_eq "yaml: an explicit empty list replaces the non-empty default" "[]" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')"
assert_eq "yaml: a tier is stamped with the team layer" "team" "$(printf '%s' "$out" | jq -r '.file_names.tiers[] | select(.name == "frozen") | ._layer')"
assert_eq "yaml: the team tiers replace the bundled ones whole" "frozen" "$(printf '%s' "$out" | jq -r '[.file_names.tiers[].name] | join(" ")')"
assert_eq "yaml: a regenerator with quotes survives" "bash gen.sh --flag 'a b' > out.json" "$(printf '%s' "$out" | jq -r '.file_names.generated[0].regenerate')"
assert_eq "yaml: a nested list survives" "generated_on" "$(printf '%s' "$out" | jq -r '.file_names.generated[0].churn[0]')"
assert_eq "yaml: redirect_map null is JSON null" "null" "$(printf '%s' "$out" | jq -c '.file_names.redirect_map')"

root="$(new_repo)"
write_yaml "$root/docs/conventions/docs-naming.local.yaml" 'generated:
  - path: "x"
    regenerate: "rm -rf /"
sweep_exclude:
  - "docs/mine/**"'
out="$(resolve "$root")"
assert_eq "yaml personal override: the regenerator is ignored" "[]" "$(printf '%s' "$out" | jq -c '.file_names.generated')"
assert_contains "yaml personal override: the declaration is reported inert" "$(layers "$root")" "!inert:generated	personal-override"
assert_contains "yaml personal override: an addition is still made" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')" '"docs/mine/**"'

root="$(new_repo)"
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^ok$"
roots: {path: docs}'
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_eq "bad yaml: exits 2" "2" "$(
  resolve "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_contains "bad yaml: the file is named" "$err" "$root/docs/conventions/docs-naming.yaml"
assert_contains "bad yaml: the line is named" "$err" "line 2"

root="$(new_repo)"
mkdir -p "$root/conf"
cat >"$root/AGENTS.md" <<'EOF'
<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `conf`, read the topic file there first.
<!-- END GENERATED: convention-home -->
EOF
write_yaml "$root/conf/docs-naming.yaml" 'regex: "^bound-home$"'
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^default-home$"'
assert_eq "convention home: the bound home supplies the team layer" "^bound-home$" "$(resolve "$root" | jq -r '.file_names.regex')"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "convention home: paths names the bound file" "$out" "team	$root/conf/docs-naming.yaml	present"

home="$TEST_TMPDIR/yroot/home"
mkdir -p "$home/docs/conventions"
write_yaml "$home/docs/conventions/docs-naming.yaml" 'regex: "^not-a-team-layer$"'
out="$(bash "$SUT" resolve --root "$home" --home "$home")"
assert_eq "yaml home root: the YAML under a home directory is not a team layer" "$(jq -r '.file_names.regex' "$SCRIPT_DIR/../skills/setup/templates/docs-naming.json")" "$(printf '%s' "$out" | jq -r '.file_names.regex')"

root="$(new_root)"
cat >"$root/AGENTS.md" <<'EOF'
<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `missing-dir`, read the topic file there first.
<!-- END GENERATED: convention-home -->
EOF
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^default-home$"'
out="$(resolve "$root" 2>&1)"
assert_eq "convention home: a dangling pointer exits 2" "2" "$?"
assert_contains "convention home: a dangling pointer names the resolver failure" "$out" "convention home"
assert_lacks "convention home: a dangling pointer does not read the default home" "$out" "^default-home$"

root="$(new_root)"
printf '<!-- BEGIN GENERATED: convention-home -->\ndeclined\n<!-- END GENERATED: convention-home -->\n' >"$root/AGENTS.md"
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^default-home$"'
assert_eq "convention home: a declined home reads docs/conventions" "^default-home$" "$(resolve "$root" | jq -r '.file_names.regex')"

for value in 'regex:' 'regex:   # todo'; do
  root="$(new_root)"
  write_yaml "$root/docs/conventions/docs-naming.yaml" "$value"
  out="$(resolve "$root" 2>&1)"
  assert_eq "empty yaml value ($value): resolve exits 2" "2" "$?"
  assert_contains "empty yaml value ($value): names the key and line" "$out" 'line 1: empty value for "regex"'
done
root="$(new_root)"
write_yaml "$root/docs/conventions/docs-naming.yaml" "$(printf 'roots:\n- docs\nexempt_paths: []\nredirect_map: null')"
assert_eq "yaml: a compact sequence, an empty list and null still parse" '["docs"] [] null' "$(resolve "$root" | jq -r '[.file_names.roots, .file_names.exempt_paths, .file_names.redirect_map] | map(tojson) | join(" ")')"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
