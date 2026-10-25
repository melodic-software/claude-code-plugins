#!/usr/bin/env bash
# Self-contained tests for resolve-config.sh: it ships inside the plugin, so the
# suite must run wherever the plugin is installed.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/resolve-config.sh"
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

assert_lacks() {
  case "$2" in
  *"$3"*) fail "$1" "does not contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}

# The empty HOME that sits beside a fixture root (`<case>/repo` and `<case>/home`).
# It is a sibling, never inside the root: a root that contains the home is a home
# root and has no team layer.
home_of() {
  printf '%s' "${1%/repo}/home"
}

# A fresh consumer git repository with an empty HOME beside it, so no layer is
# present until a case writes one.
new_root() {
  root="$TEST_TMPDIR/case-$CASES-$RANDOM/repo"
  mkdir -p "$root/.claude" "$(home_of "$root")"
  git init -q "$root" >/dev/null 2>&1
  printf '%s' "$root"
}

write_layer() {
  # write_layer <path> <file_names-json> [schema]
  schema="${3:-1}"
  mkdir -p "$(dirname "$1")"
  printf '{"schema": %s, "file_names": %s}\n' "$schema" "$2" >"$1"
}

resolve() {
  # resolve <root> [extra args...]
  r="$1"
  shift
  bash "$SUT" resolve --root "$r" --home "$(home_of "$r")" "$@"
}

layers() {
  r="$1"
  shift
  bash "$SUT" layers --root "$r" --home "$(home_of "$r")" "$@"
}

# 1. Every layer absent resolves to the bundled defaults.
root="$(new_root)"
out="$(resolve "$root")"
assert_eq "no layers: rule is the bundled lower-kebab" "lower-kebab" "$(printf '%s' "$out" | jq -r '.file_names.rule')"
assert_eq "no layers: roots is the bundled docs" "docs" "$(printf '%s' "$out" | jq -r '.file_names.roots[0]')"
assert_eq "no layers: schema is stamped" "1" "$(printf '%s' "$out" | jq -r '.schema')"
assert_eq "no layers: every key is provenance bundled" "" "$(layers "$root" | grep -v 'bundled$' || true)"

# 2. The team layer supplies a nearest-wins key whole.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.json" '{"regex": "^team$"}'
assert_eq "team layer: regex overrides the default" "^team$" "$(resolve "$root" | jq -r '.file_names.regex')"
assert_contains "team layer: provenance names it" "$(layers "$root")" "regex	bundled,team"

# 3. The overlay beats the team layer on a nearest-wins key.
write_layer "$root/.claude/docs-naming.local.json" '{"regex": "^overlay$"}'
assert_eq "overlay: nearest wins on regex" "^overlay$" "$(resolve "$root" | jq -r '.file_names.regex')"

# 3b. And the team layer beats the USER-GLOBAL one, because the team layer is
#     nearer. The additive class needs the opposite layer order, so this is the
#     case that keeps the two from being collapsed into one loop again: a
#     machine-wide rule must never decide what a repository enforces.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.json" '{"rule": "team-rule", "regex": "^team$"}'
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"rule": "user-rule", "regex": "^user$"}'
assert_eq "team beats user-global on rule" "team-rule" "$(resolve "$root" | jq -r '.file_names.rule')"
assert_eq "team beats user-global on regex" "^team$" "$(resolve "$root" | jq -r '.file_names.regex')"
assert_contains "provenance lists both, team last" "$(layers "$root")" "rule	bundled,user-global,team"

# 4. On an additive key the team layer REPLACES the bundled default, and a
#    personal layer only adds to what the team decided.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.json" '{"sweep_exclude": ["docs/frozen/**"]}'
write_layer "$root/.claude/docs-naming.local.json" '{"sweep_exclude": ["docs/mine/**"]}'
out="$(resolve "$root" | jq -c '.file_names.sweep_exclude')"
assert_contains "additive: the team entry survives the overlay" "$out" '"docs/frozen/**"'
assert_contains "additive: the overlay entry is added" "$out" '"docs/mine/**"'
assert_lacks "additive: the team layer replaced the bundled default" "$out" '".work/**"'

# 4b. With no team layer, a personal layer adds to the bundled default.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.local.json" '{"sweep_exclude": ["docs/mine/**"]}'
out="$(resolve "$root" | jq -c '.file_names.sweep_exclude')"
assert_contains "additive: the bundled default survives a personal addition" "$out" '".work/**"'
assert_contains "additive: the personal entry is added to it" "$out" '"docs/mine/**"'

# 5. A personal layer cannot shrink a policy-floor list: an overlay `tiers` that
#    omits the frozen released tier still resolves with it present.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.local.json" '{"tiers": [{"name": "mine", "paths": ["docs/x/**"], "forms": "all"}]}'
names="$(resolve "$root" | jq -r '.file_names.tiers[].name' | sort | tr '\n' ' ')"
assert_eq "policy floor: the overlay adds a tier and removes none" "historical mine released " "$names"

# 6. `generated` is team-layer only: an overlay declaration is inert.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.local.json" '{"generated": [{"path": "x", "regenerate": "rm -rf /"}]}'
out="$(resolve "$root" | jq -c '.file_names.generated')"
assert_eq "team-only: the overlay regenerator is ignored" "[]" "$out"
assert_contains "team-only: the overlay declaration is reported inert" "$(layers "$root")" "!inert:generated	overlay"

# 7. The same holds for the user-global layer.
root="$(new_root)"
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"generated": [{"path": "y", "regenerate": "true"}]}'
assert_eq "team-only: the user-global regenerator is ignored" "[]" "$(resolve "$root" | jq -c '.file_names.generated')"
assert_contains "team-only: the user-global declaration is reported inert" "$(layers "$root")" "!inert:generated	user-global"

# 8. A team layer DOES supply `generated`.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.json" '{"generated": [{"path": "build/out.json", "regenerate": "make out"}]}'
assert_eq "team layer supplies the regenerator" "build/out.json" "$(resolve "$root" | jq -r '.file_names.generated[0].path')"

# 9. Malformed JSON is fatal and names the file.
root="$(new_root)"
printf '{not json' >"$root/.claude/docs-naming.json"
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_eq "malformed team layer exits 2" "2" "$(
  resolve "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_contains "malformed team layer is named" "$err" "docs-naming.json"

# 10. A missing schema is fatal.
root="$(new_root)"
printf '{"file_names": {"rule": "lower-kebab"}}\n' >"$root/.claude/docs-naming.json"
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_contains "missing schema is refused" "$err" "schema 'missing'"

# 11. An unknown schema is fatal.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.json" '{"rule": "lower-kebab"}' 99
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_contains "unknown schema is refused" "$err" "schema '99'"

# 12. A jq that emits CRLF (native Windows behavior) still resolves clean values.
root="$(new_root)"
mkdir -p "$root/bin"
{
  printf '#!/usr/bin/env bash\n'
  printf 'REAL=%q\n' "$(command -v jq)"
  # shellcheck disable=SC2016  # the body of the stub script, expanded when it runs, not here
  printf '"$REAL" "$@" | sed "s/$/\\r/"\n'
} >"$root/bin/jq"
chmod +x "$root/bin/jq"
write_layer "$root/.claude/docs-naming.json" '{"regex": "^crlf$"}'
out="$(PATH="$root/bin:$PATH" resolve "$root" | jq -r '.file_names.regex')"
assert_eq "CRLF jq: the resolved regex carries no carriage return" "^crlf$" "$out"

# 13. Usage errors exit 2.
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

# 14. `paths` reports each layer's location and presence.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.json" '{}'
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "paths: the pre-YAML team layer is deprecated" "$out" "team	$root/.claude/docs-naming.json	deprecated"
assert_contains "paths: the overlay is absent, at its YAML path" "$out" "overlay	$root/docs/conventions/docs-naming.local.yaml	absent"

# 15. With no --root the resolver takes the git toplevel of the working
#     directory, never the directory the script lives in.
root="$(new_root)"
git init -q "$root" >/dev/null 2>&1
git -C "$root" config user.email fixture@example.invalid
git -C "$root" config user.name "Fixture"
git -C "$root" config commit.gpgsign false
write_layer "$root/.claude/docs-naming.json" '{"regex": "^from-cwd$"}'
out="$(cd "$root" && HOME="$(home_of "$root")" bash "$SUT" resolve | jq -r '.file_names.regex')"
assert_eq "no --root: the git toplevel of the cwd supplies the team layer" "^from-cwd$" "$out"

# Every tier entry carries the layer that contributed it, which is what lets a
# consumer hold the policy floor per file rather than per key.
root="$(new_root)"
write_layer "$root/.claude/docs-naming.json" \
  '{"tiers": [{"name": "t-team", "paths": ["docs/a/**"], "forms": "none"}]}'
write_layer "$(home_of "$root")/.claude/docs-naming.json" \
  '{"tiers": [{"name": "t-personal", "paths": ["docs/a/deep/**"], "forms": "all"}]}'
tiers="$(resolve "$root" | jq -c '.file_names.tiers')"
assert_contains "a team tier is stamped team" "$tiers" '"name":"t-team"'
assert_contains "and carries its layer" "$tiers" '"_layer":"team"'
assert_contains "a personal tier is still appended" "$tiers" '"name":"t-personal"'
assert_contains "and is stamped with the layer that added it" "$tiers" '"_layer":"user-global"'

# Config-cascade step 2: a home or non-repo root has no team or overlay layer, and
# the user-global file is read once, never again as team.
home="$TEST_TMPDIR/hroot/home"
mkdir -p "$home/.claude"
write_layer "$home/.claude/docs-naming.json" '{"rule": "home-rule", "generated": [{"path": "y", "regenerate": "true"}]}'
out="$(bash "$SUT" resolve --root "$home" --home "$home")"
assert_eq "home root: the user-global file supplies its nearest-wins key" "home-rule" "$(printf '%s' "$out" | jq -r '.file_names.rule')"
assert_eq "home root: a team-only key in the user-global file is not read as team" "null" "$(printf '%s' "$out" | jq -c '[.file_names.generated[].path] | index("y")')"
out="$(bash "$SUT" layers --root "$home" --home "$home")"
assert_contains "home root: provenance names the user-global layer once" "$out" "rule	bundled,user-global
"
assert_lacks "home root: provenance never names the team layer" "$out" ",team"
out="$(bash "$SUT" paths --root "$home" --home "$home")"
assert_contains "home root: paths marks team not-applicable" "$out" "team	-	not-applicable: home root"
assert_contains "home root: paths marks the overlay not-applicable" "$out" "overlay	-	not-applicable: home root"

# An ancestor of the home is a home root too.
parent="$TEST_TMPDIR/hroot"
mkdir -p "$parent/.claude"
write_layer "$parent/.claude/docs-naming.json" '{"rule": "ancestor-rule"}'
out="$(bash "$SUT" resolve --root "$parent" --home "$home")"
assert_eq "an ancestor of the home is a home root: its .claude is not the team layer" "home-rule" "$(printf '%s' "$out" | jq -r '.file_names.rule')"

# A git repository at the home directory is still a home root.
git init -q "$home" >/dev/null 2>&1
out="$(bash "$SUT" paths --root "$home" --home "$home")"
assert_contains "a git repository at the home is still a home root" "$out" "team	-	not-applicable: home root"

# A directory that is not a git working tree has no team or overlay layer.
plain="$TEST_TMPDIR/plain"
mkdir -p "$plain/.claude" "$TEST_TMPDIR/plainhome"
write_layer "$plain/.claude/docs-naming.json" '{"rule": "plain-team"}'
write_layer "$plain/.claude/docs-naming.local.json" '{"rule": "plain-overlay"}'
out="$(bash "$SUT" resolve --root "$plain" --home "$TEST_TMPDIR/plainhome")"
assert_eq "a non-repo root: the bundled rule stands" "lower-kebab" "$(printf '%s' "$out" | jq -r '.file_names.rule')"
out="$(bash "$SUT" paths --root "$plain" --home "$TEST_TMPDIR/plainhome")"
assert_contains "a non-repo root: paths marks team not-applicable" "$out" "team	-	not-applicable: non-repo root"

# A repository whose team file is the user-global file (a symlinked .claude) reads
# it once.
root="$(new_root)"
rm -rf "$root/.claude"
ln -s "$(home_of "$root")/.claude" "$root/.claude" 2>/dev/null || true
if [[ -L "$root/.claude" ]]; then
  write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"rule": "shared-rule"}'
  out="$(bash "$SUT" layers --root "$root" --home "$(home_of "$root")")"
  assert_contains "a team path that is the user-global file: read once" "$out" "rule	bundled,user-global
"
  out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
  assert_contains "a team path that is the user-global file: paths says so" "$out" "team	-	same file as the user-global layer"
fi

# The retired docs-hygiene name is read when the docs-naming file is absent, with
# a stderr WARN on `resolve` and the state `legacy` on `paths`; the new name wins
# whenever it exists.
root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.json" '{"regex": "^retired$"}'
write_layer "$root/.claude/docs-hygiene.local.json" '{"exempt_paths": ["docs/retired/**"]}'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
err="$(cat "$TEST_TMPDIR/err")"
assert_eq "retired name: the team layer is still read" "^retired$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_contains "retired name: the overlay is still read" "$(printf '%s' "$out" | jq -c '.file_names.exempt_paths')" '"docs/retired/**"'
assert_contains "retired name: resolve warns and names the file" "$err" "WARN: reading $root/.claude/docs-hygiene.json, the retired name; rename it to $root/.claude/docs-naming.json"
assert_contains "retired name: the overlay is named too" "$err" "$root/.claude/docs-naming.local.json"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "retired name: paths reports the team layer as legacy" "$out" "team	$root/.claude/docs-hygiene.json	legacy"
assert_eq "retired name: layers stays quiet on stderr" "" "$(layers "$root" 2>&1 >/dev/null)"
write_layer "$root/.claude/docs-naming.json" '{"regex": "^current$"}'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
assert_eq "retired name: the new name wins when both exist" "^current$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_lacks "retired name: no warning for a layer that has a new-name file" "$(cat "$TEST_TMPDIR/err")" "docs-hygiene.json"

# --- the YAML layers under the convention home --------------------------------

new_repo() {
  new_root
}

write_yaml() {
  # write_yaml <path> <content>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}

# The team YAML supplies a nearest-wins key, and the resolver names the layer.
root="$(new_repo)"
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^yaml-team$"'
assert_eq "yaml team layer: regex overrides the default" "^yaml-team$" "$(resolve "$root" | jq -r '.file_names.regex')"
assert_contains "yaml team layer: provenance names the team layer" "$(layers "$root")" "regex	bundled,team"
assert_contains "yaml team layer: a key it does not set stays bundled" "$(layers "$root")" "rule	bundled
"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "yaml team layer: paths names the file and says present" "$out" "team	$root/docs/conventions/docs-naming.yaml	present"
assert_eq "yaml team layer: resolve is quiet on stderr" "" "$(resolve "$root" 2>&1 >/dev/null)"

# The YAML wins when both it and the pre-YAML file exist, and the two are never merged.
root="$(new_repo)"
write_layer "$root/.claude/docs-naming.json" '{"regex": "^old$", "sweep_exclude": ["docs/old/**"]}'
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^new$"'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
assert_eq "both exist: the YAML supplies the regex" "^new$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_lacks "both exist: nothing from the JSON is merged in" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')" "docs/old/**"
assert_eq "both exist: no warning, the JSON is not read" "" "$(cat "$TEST_TMPDIR/err")"
out="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "both exist: paths reports the YAML" "$out" "team	$root/docs/conventions/docs-naming.yaml	present"

# The pre-YAML location is read when the YAML is absent, and paths says so.
root="$(new_repo)"
write_layer "$root/.claude/docs-naming.json" '{"regex": "^old$"}'
write_layer "$root/.claude/docs-naming.local.json" '{"sweep_exclude": ["docs/mine/**"]}'
out="$(resolve "$root" 2>"$TEST_TMPDIR/err")"
assert_eq "no YAML: the old team layer is read" "^old$" "$(printf '%s' "$out" | jq -r '.file_names.regex')"
assert_contains "no YAML: the old overlay is read" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')" '"docs/mine/**"'
assert_eq "no YAML: resolve stays quiet on stderr, which skill scripts pass through" "" "$(cat "$TEST_TMPDIR/err")"
pout="$(bash "$SUT" paths --root "$root" --home "$(home_of "$root")")"
assert_contains "no YAML: paths reports the team layer as deprecated" "$pout" "team	$root/.claude/docs-naming.json	deprecated"
assert_contains "no YAML: paths reports the overlay as deprecated" "$pout" "overlay	$root/.claude/docs-naming.local.json	deprecated"
assert_contains "no YAML: provenance still names the team layer" "$(layers "$root")" "regex	bundled,team"

# The resolver names the layer that supplied each value, across all three layers.
root="$(new_repo)"
write_layer "$(home_of "$root")/.claude/docs-naming.json" '{"rule": "user-rule", "regex": "^user$", "exempt_extensions": ["rb"]}'
write_yaml "$root/docs/conventions/docs-naming.yaml" 'regex: "^team$"
exempt_basenames:
  - "TEAM.md"'
write_yaml "$root/docs/conventions/docs-naming.local.yaml" 'exempt_basenames:
  - "MINE.md"'
lay="$(layers "$root")"
assert_contains "provenance: a nearest-wins key lists user-global then team" "$lay" "regex	bundled,user-global,team"
assert_contains "provenance: the user-global rule survives where the team sets none" "$lay" "rule	bundled,user-global"
assert_contains "provenance: an additive key lists team then overlay" "$lay" "exempt_basenames	bundled,team,overlay"
assert_contains "provenance: an additive key the user-global sets" "$lay" "exempt_extensions	bundled,user-global"
assert_eq "provenance: the team basenames replace the default, the overlay adds" "TEAM.md MINE.md" "$(resolve "$root" | jq -r '.file_names.exempt_basenames | join(" ")')"

# Value fidelity: root objects, tiers stamped with their layer, an explicit empty
# list replacing a non-empty default, and a null redirect_map.
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

# The overlay YAML is held to the same policy floor as the JSON overlay.
root="$(new_repo)"
write_yaml "$root/docs/conventions/docs-naming.local.yaml" 'generated:
  - path: "x"
    regenerate: "rm -rf /"
sweep_exclude:
  - "docs/mine/**"'
out="$(resolve "$root")"
assert_eq "yaml overlay: the regenerator is ignored" "[]" "$(printf '%s' "$out" | jq -c '.file_names.generated')"
assert_contains "yaml overlay: the declaration is reported inert" "$(layers "$root")" "!inert:generated	overlay"
assert_contains "yaml overlay: an addition is still made" "$(printf '%s' "$out" | jq -c '.file_names.sweep_exclude')" '"docs/mine/**"'

# A YAML layer the parser rejects is fatal and names the file and the line.
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

# The team YAML sits under the convention home the repository binds.
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

# A home root still has no team YAML.
home="$TEST_TMPDIR/yroot/home"
mkdir -p "$home/docs/conventions"
write_yaml "$home/docs/conventions/docs-naming.yaml" 'regex: "^not-a-team-layer$"'
out="$(bash "$SUT" resolve --root "$home" --home "$home")"
assert_eq "yaml home root: the YAML under a home directory is not a team layer" "$(jq -r '.file_names.regex' "$SCRIPT_DIR/../skills/setup/templates/docs-naming.json")" "$(printf '%s' "$out" | jq -r '.file_names.regex')"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
