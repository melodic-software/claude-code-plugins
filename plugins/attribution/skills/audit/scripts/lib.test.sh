#!/usr/bin/env bash
# Self-contained tests for lib.sh's config reader. Fixtures are built inline in a
# tmpdir. Per the shell-test-helpers convention, assertion helpers are local.
#
# The load-bearing cases are the per-file fallback: the YAML layer replaces the
# JSON one whole when both exist, the JSON is read when the YAML is absent, and
# every value names the layer that supplied it.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (the legacy layers are JSON)" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed (team layers apply only in a repository)" >&2
  exit 0
fi

export HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME/.claude"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}

# --- Fixtures --------------------------------------------------------------------

ROOT="$TEST_TMPDIR/repo"
mkdir -p "$ROOT/.claude" "$ROOT/docs/conventions"
git init -q "$ROOT"
JSON_TEAM="$ROOT/.claude/attribution.json"
JSON_LOCAL="$ROOT/.claude/attribution.local.json"
YAML_TEAM="$ROOT/docs/conventions/attribution.yaml"
YAML_LOCAL="$ROOT/docs/conventions/attribution.local.yaml"
USER_JSON="$HOME/.claude/attribution.json"

reset() { rm -f "$JSON_TEAM" "$JSON_LOCAL" "$YAML_TEAM" "$YAML_LOCAL" "$USER_JSON"; }

layers() { printf '%s\n' ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; }

v=""
list=()

# --- The old location, read when the YAML is absent -------------------------------

reset
printf '%s\n' '{"stamp_expiry_days": 30, "gates": {"min_n_per_class": 4}, "excluded_paths": ["a/**", "b c/**"]}' >"$JSON_TEAM"
cfg_layers_init "$ROOT"
assert_eq "with no YAML the JSON team file is the layer" "$(layers)" "$JSON_TEAM"
cfg_scalar v stamp_expiry_days
assert_eq "a JSON scalar is read" "$v" "30"
assert_eq "a JSON scalar names its layer" "$CFG_SOURCE" "$JSON_TEAM"
cfg_scalar v gates.min_n_per_class
assert_eq "a dotted key reads a nested JSON value" "$v" "4"
list=()
cfg_list list excluded_paths
assert_eq "a JSON list is read, one element per entry" "$(printf '%s|' "${list[@]}")" "a/**|b c/**|"
assert_eq "a JSON list names its layer" "$CFG_SOURCE" "$JSON_TEAM"

# --- The YAML wins when both exist -------------------------------------------------

printf '%s\n' 'stamp_expiry_days: 60' 'excluded_paths:' '  - y/**' >"$YAML_TEAM"
cfg_layers_init "$ROOT"
assert_eq "with both present only the YAML team file is a layer" "$(layers)" "$YAML_TEAM"
cfg_scalar v stamp_expiry_days
assert_eq "the YAML value wins" "$v" "60"
assert_eq "the YAML value names the YAML layer" "$CFG_SOURCE" "$YAML_TEAM"
cfg_scalar v gates.min_n_per_class
assert_eq "a key only the shadowed JSON sets is not read" "$v" ""
assert_eq "an unsupplied value names no layer" "$CFG_SOURCE" ""
list=()
cfg_list list excluded_paths
assert_eq "a YAML block list is read" "$(printf '%s|' "${list[@]}")" "y/**|"
assert_eq "a YAML list names its layer" "$CFG_SOURCE" "$YAML_TEAM"

# --- Overlays, the user-global layer, and per-file fallback per layer ------------

printf '%s\n' '{"stamp_expiry_days": 75}' >"$JSON_LOCAL"
cfg_layers_init "$ROOT"
assert_eq "a YAML team layer sits beside a JSON overlay when the YAML overlay is absent" \
  "$(layers)" "$YAML_TEAM"$'\n'"$JSON_LOCAL"
cfg_scalar v stamp_expiry_days
assert_eq "the JSON overlay refines the YAML team layer" "$v|$CFG_SOURCE" "75|$JSON_LOCAL"

printf '%s\n' 'stamp_expiry_days: 90' 'excluded_paths: []' >"$YAML_LOCAL"
cfg_layers_init "$ROOT"
assert_eq "the YAML overlay replaces the JSON overlay" "$(layers)" "$YAML_TEAM"$'\n'"$YAML_LOCAL"
cfg_scalar v stamp_expiry_days
assert_eq "the YAML overlay supplies the value" "$v|$CFG_SOURCE" "90|$YAML_LOCAL"
list=(stale)
cfg_list list excluded_paths
assert_eq "an empty YAML overlay list clears the team list" "${#list[@]}|$CFG_SOURCE" "0|$YAML_LOCAL"

printf '%s\n' '{"trigger_less_stamp_check": true}' >"$USER_JSON"
cfg_layers_init "$ROOT"
cfg_scalar v trigger_less_stamp_check
assert_eq "the user-global layer supplies a key no repo layer sets" "$v|$CFG_SOURCE" "true|$USER_JSON"

# --- Validation keeps an earlier valid value standing -----------------------------

reset
printf '%s\n' 'budgets:' '  corpus_fetch_ceiling: 40' >"$YAML_TEAM"
printf '%s\n' 'budgets:' '  corpus_fetch_ceiling: many' >"$YAML_LOCAL"
cfg_layers_init "$ROOT"
cfg_scalar v budgets.corpus_fetch_ceiling '^[0-9]+$'
assert_eq "a value failing the pattern leaves the earlier one" "$v|$CFG_SOURCE" "40|$YAML_TEAM"

# A YAML layer outside the parser's subset is named on stderr and skipped whole.
printf '%s\n' 'budgets: {corpus_fetch_ceiling: 5}' >"$YAML_LOCAL"
err="$(cfg_layers_init "$ROOT" 2>&1 >/dev/null)"
assert_eq "an unparseable YAML layer is named on stderr" \
  "$([[ "$err" == *"$YAML_LOCAL does not parse"* ]] && echo named || echo "$err")" "named"
cfg_layers_init "$ROOT" 2>/dev/null
assert_eq "an unparseable YAML layer is not a layer" "$(layers)" "$YAML_TEAM"
cfg_scalar v budgets.corpus_fetch_ceiling
assert_eq "an unparseable YAML layer supplies nothing" "$v|$CFG_SOURCE" "40|$YAML_TEAM"

# A list key is present after a byte-order mark and when quoted.
printf '\xEF\xBB\xBF%s\n' 'excluded_paths: []' >"$YAML_LOCAL"
printf '%s\n' '"excluded_paths":' '  - "**/fixtures/**"' >"$YAML_TEAM"
cfg_layers_init "$ROOT"
list=(stale)
cfg_list list excluded_paths
assert_eq "an empty list after a byte-order mark still clears" "${#list[@]}|$CFG_SOURCE" "0|$YAML_LOCAL"
rm -f "$YAML_LOCAL"
cfg_layers_init "$ROOT"
cfg_list list excluded_paths
assert_eq "a quoted key and a quoted glob are read" "$(printf '%s|' "${list[@]}")|$CFG_SOURCE" "**/fixtures/**||$YAML_TEAM"

# A JSON list key holding a non-list clears the list, as it did before.
reset
printf '%s\n' '{"excluded_paths": ["a/**"]}' >"$JSON_TEAM"
printf '%s\n' '{"excluded_paths": false}' >"$JSON_LOCAL"
cfg_layers_init "$ROOT"
list=(stale)
cfg_list list excluded_paths
assert_eq "a JSON non-list value clears the list" "${#list[@]}|$CFG_SOURCE" "0|$JSON_LOCAL"

# --- The bound convention home ----------------------------------------------------

reset
mkdir -p "$ROOT/config"
# shellcheck disable=SC2016  # the backticks are the pointer line's own markup
printf '%s\n' '<!-- BEGIN GENERATED: convention-home -->' \
  'Team conventions live in `config`.' \
  '<!-- END GENERATED: convention-home -->' >"$ROOT/AGENTS.md"
printf '%s\n' 'stamp_expiry_days: 10' >"$ROOT/config/attribution.yaml"
printf '%s\n' 'stamp_expiry_days: 20' >"$YAML_TEAM"
cfg_layers_init "$ROOT"
cfg_scalar v stamp_expiry_days
assert_eq "the team YAML is read from the bound home" "$v|$CFG_SOURCE" "10|$ROOT/config/attribution.yaml"
rm -rf "$ROOT/AGENTS.md" "$ROOT/config"

# --- No team layer outside a repository --------------------------------------------

NONREPO="$TEST_TMPDIR/loose"
mkdir -p "$NONREPO/docs/conventions"
printf '%s\n' 'stamp_expiry_days: 5' >"$NONREPO/docs/conventions/attribution.yaml"
cfg_layers_init "$NONREPO"
assert_eq "a non-repo root has no team layer" "${#CFG_LAYERS[@]}" "0"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
