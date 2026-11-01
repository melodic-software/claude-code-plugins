#!/usr/bin/env bash
# Tests for migrate-binding.sh: a legacy JSON binding and overlay move under
# tracker: in <home>/work-items.yaml and <home>/work-items.local.yaml.
set -uo pipefail

FAILED=0
CASE_NUM=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/migrate-binding.sh"
LIB_DIR="$SCRIPT_DIR/../../../tools/work-item-tracker/lib"
# shellcheck source=../../../tools/work-item-tracker/tests/lib.sh
source "$LIB_DIR/../tests/lib.sh"
# shellcheck source=../../../tools/work-item-tracker/lib/binding.sh
source "$LIB_DIR/binding.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"
command -v git >/dev/null 2>&1 || skip_suite "git not installed"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR

# repo <name>: a fresh git repository, echoed.
repo() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir"
  git init -q "$dir"
  printf '%s\n' "$dir"
}

run() {
  OUT="$(bash "$SCRIPT" --root "$1" 2>&1)"
  RC=$?
}

# assert_file <label> present|absent <path>...: every path is present, or none is.
assert_file() {
  local label="$1" want="$2" path got="$2"
  shift 2
  for path in "$@"; do
    if [[ -e "$path" && "$want" == "absent" ]]; then got="present"; fi
    if [[ ! -e "$path" && "$want" == "present" ]]; then got="absent"; fi
  done
  assert_eq "$label" "$want" "$got"
}

# --- nothing to migrate ---

EMPTY="$(repo empty)"
run "$EMPTY"
assert_eq "no legacy file exits 0" "0" "$RC"
assert_eq "no legacy file prints none" "none" "$OUT"

# --- binding plus overlay into the default home, beside other settings ---

MAIN="$(repo main)"
mkdir -p "$MAIN/docs/conventions"
printf '%s' 'ai_disclaimer: false' >"$MAIN/docs/conventions/work-items.yaml"
printf '%s\n' '{"schema_version":"1.0","provider":"github","docs":"Work-item tracker binding: see CONTRACT.md","config":{"lease_ttl_hours":24,"role_labels":{"human-gated":"hold"},"github":{"wont_do_labels":["wontfix","invalid"]}}}' \
  >"$MAIN/.work-item-tracker.json"
printf '%s\n' '{"config":{"lease_ttl_hours":6}}' >"$MAIN/.work-item-tracker.local.json"
run "$MAIN"
assert_eq "binding plus overlay migrates with exit 0" "0" "$RC"
assert_contains "announces the binding move" "$OUT" "migrated $MAIN/.work-item-tracker.json $MAIN/docs/conventions/work-items.yaml"
assert_contains "announces the overlay move" "$OUT" "migrated $MAIN/.work-item-tracker.local.json $MAIN/docs/conventions/work-items.local.yaml"
assert_contains "announces the binding removal" "$OUT" "removed $MAIN/.work-item-tracker.json"
assert_contains "announces the overlay removal" "$OUT" "removed $MAIN/.work-item-tracker.local.json"
assert_file "legacy binding removed" absent "$MAIN/.work-item-tracker.json"
assert_file "legacy overlay removed" absent "$MAIN/.work-item-tracker.local.json"
assert_eq "existing settings in work-items.yaml are kept" "false" \
  "$(awk -f "$WIT_YAML_PARSER" "$MAIN/docs/conventions/work-items.yaml" | awk -F '\t' '$1 == "ai_disclaimer" { print $2 }')"
FOUND="$(CLAUDE_PROJECT_DIR="$MAIN" wit_find_binding)"
assert_eq "the seam now finds the YAML binding" "$MAIN/docs/conventions/work-items.yaml" "$FOUND"
if CLAUDE_PROJECT_DIR="$MAIN" wit_read_binding "$FOUND" 2>"$TEST_TMPDIR/main.err"; then
  pass "migrated binding validates"
  assert_eq "provider carried over" "github" "$WIT_PROVIDER"
  assert_eq "overlay lease_ttl_hours wins over the team value" "6" "$WIT_LEASE_TTL_HOURS"
  assert_eq "role label remap carried over" "hold" "$WIT_HUMAN_GATED_LABEL"
else
  fail "migrated binding validates" "success" "$(<"$TEST_TMPDIR/main.err")"
fi
assert_not_contains "no legacy notice after the move" "$(<"$TEST_TMPDIR/main.err")" "notice"
assert_eq "string lists carried over" '["wontfix","invalid"]' \
  "$(wit_yaml_binding_json "$FOUND" | jq -c '.config.github.wont_do_labels')"

# --- jira shape: digit-string ids stay strings, an empty list stays [] ---

JIRA="$(repo jira)"
printf '%s\n' '{"schema_version":"1.0","provider":"jira","config":{"lease_ttl_hours":24,"jira":{"site":"a.atlassian.net","project_keys":["ENG"],"done_category_keys":[],"resolutions":{"completed":["10000"],"wont_do":[]}}}}' \
  >"$JIRA/.work-item-tracker.json"
run "$JIRA"
assert_eq "jira binding migrates with exit 0" "0" "$RC"
assert_eq "jira config reads back unchanged" \
  '{"done_category_keys":[],"project_keys":["ENG"],"resolutions":{"completed":["10000"],"wont_do":[]},"site":"a.atlassian.net"}' \
  "$(wit_yaml_binding_json "$JIRA/docs/conventions/work-items.yaml" | jq -c -S '.config.jira')"

# --- the home the pointer region binds ---

POINTED="$(repo pointed)"
mkdir -p "$POINTED/team/conf"
# shellcheck disable=SC2016 # the backticks are the pointer grammar, not a command substitution
printf '%s\n' '<!-- BEGIN GENERATED: convention-home -->' 'Conventions live in `team/conf`.' '<!-- END GENERATED: convention-home -->' >"$POINTED/AGENTS.md"
printf '%s\n' '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}' >"$POINTED/.work-item-tracker.json"
run "$POINTED"
assert_eq "pointer-bound home migrates with exit 0" "0" "$RC"
assert_eq "binding lands in the bound home" "$POINTED/team/conf/work-items.yaml" "$(CLAUDE_PROJECT_DIR="$POINTED" wit_find_binding)"

# --- refusals leave every file as it was ---

CONFLICT="$(repo conflict)"
mkdir -p "$CONFLICT/docs/conventions"
printf '%s\n' 'tracker:' '  provider: github' >"$CONFLICT/docs/conventions/work-items.yaml"
printf '%s\n' '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}' >"$CONFLICT/.work-item-tracker.json"
BEFORE="$(<"$CONFLICT/docs/conventions/work-items.yaml")"
run "$CONFLICT"
assert_eq "an existing tracker key refuses with exit 1" "1" "$RC"
assert_contains "the refusal names the target" "$OUT" "refused: $CONFLICT/docs/conventions/work-items.yaml already sets tracker:"
assert_eq "the target is untouched" "$BEFORE" "$(<"$CONFLICT/docs/conventions/work-items.yaml")"
assert_file "legacy binding kept on refusal" present "$CONFLICT/.work-item-tracker.json"

NESTED="$(repo nested)"
printf '%s\n' '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"x":[["a"]]}}' >"$NESTED/.work-item-tracker.json"
printf '%s\n' '{"config":{"lease_ttl_hours":6}}' >"$NESTED/.work-item-tracker.local.json"
run "$NESTED"
assert_eq "a nested list refuses with exit 1" "1" "$RC"
assert_file "a refusal writes neither target" absent \
  "$NESTED/docs/conventions/work-items.yaml" "$NESTED/docs/conventions/work-items.local.yaml"
assert_file "overlay kept when the binding refuses" present "$NESTED/.work-item-tracker.local.json"

UNKNOWN="$(repo unknown)"
printf '%s\n' '{"schema_version":"1.0","provider":"github","extra":"x","config":{"lease_ttl_hours":24}}' >"$UNKNOWN/.work-item-tracker.json"
run "$UNKNOWN"
assert_eq "a key the YAML binding rejects rolls back with exit 1" "1" "$RC"
assert_file "rollback removes the new target and the home it created" absent "$UNKNOWN/docs/conventions/work-items.yaml" "$UNKNOWN/docs"

STRAY="$(repo stray-overlay)"
mkdir -p "$STRAY/docs/conventions"
printf '%s\n' 'tracker:' '  config:' '    lease_ttl_hours: 1' >"$STRAY/docs/conventions/work-items.local.yaml"
printf '%s\n' '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}' >"$STRAY/.work-item-tracker.json"
run "$STRAY"
assert_eq "a YAML overlay the legacy binding never read refuses with exit 1" "1" "$RC"
assert_file "the binding stays put beside a stray YAML overlay" absent "$STRAY/docs/conventions/work-items.yaml"
assert_file "legacy binding kept on rollback" present "$UNKNOWN/.work-item-tracker.json"

DECLINED="$(repo declined)"
printf '%s\n' '<!-- BEGIN GENERATED: convention-home -->' 'declined' '<!-- END GENERATED: convention-home -->' >"$DECLINED/AGENTS.md"
printf '%s\n' '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}' >"$DECLINED/.work-item-tracker.json"
run "$DECLINED"
assert_eq "a declined home exits 3" "3" "$RC"
assert_file "legacy binding stays when no home applies" present "$DECLINED/.work-item-tracker.json"

# --- overlay only, beside an existing YAML binding ---

OVONLY="$(repo overlay-only)"
mkdir -p "$OVONLY/docs/conventions"
printf '%s\n' 'tracker:' '  schema_version: "1.0"' '  provider: github' '  config:' '    lease_ttl_hours: 24' >"$OVONLY/docs/conventions/work-items.yaml"
printf '%s\n' '{"config":{"lease_ttl_hours":3}}' >"$OVONLY/.work-item-tracker.local.json"
run "$OVONLY"
assert_eq "overlay alone migrates with exit 0" "0" "$RC"
if CLAUDE_PROJECT_DIR="$OVONLY" wit_read_binding "$OVONLY/docs/conventions/work-items.yaml" 2>/dev/null; then
  assert_eq "the migrated overlay applies" "3" "$WIT_LEASE_TTL_HOURS"
else
  fail "the migrated overlay applies" "3" "binding failed"
fi

assert_fails "an unknown argument is a usage error" "exit 2" "exit 0" bash "$SCRIPT" --bogus

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
