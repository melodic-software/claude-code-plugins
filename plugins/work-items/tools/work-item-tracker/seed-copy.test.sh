#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# seed-copy.sh: a first run copies a seed, an untouched copy fast-forwards when the seed
# changes, and an edited copy stops with a diff and is left as it was.
# test-scope: plugins/work-items/tools/work-item-tracker/seeds/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/tests/lib.sh"
COPY="$SCRIPT_DIR/seed-copy.sh"
TRACKER="$SCRIPT_DIR/work-item-tracker.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SEEDS="$TMP_ROOT/seeds"
ROOT="$TMP_ROOT/repo"
DEST="$ROOT/tools/work-item-tracker/adapters/acme"
mkdir -p "$SEEDS/acme/schema-check" "$ROOT"
printf 'v1\n' >"$SEEDS/acme/get-item.sh"
printf '{}\n' >"$SEEDS/acme/capabilities.json"
printf 'test\n' >"$SEEDS/acme/get-item.test.sh"
printf 'mock\n' >"$SEEDS/acme/mock.sh"
printf 'check\n' >"$SEEDS/acme/schema-check/fidelity.sh"
chmod +x "$SEEDS/acme/get-item.sh"

# run_copy <args...>: OUT holds stdout, RC the exit code.
run_copy() {
  OUT="$(WIT_SEEDS_DIR="$SEEDS" bash "$COPY" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}

# --- usage -------------------------------------------------------------------
run_copy
assert_eq "no provider → exit 2" "2" "$RC"
run_copy ../acme --root "$ROOT"
assert_eq "a path-like provider → exit 2" "2" "$RC"
run_copy nope --root "$ROOT"
assert_eq "an unknown seed → exit 2" "2" "$RC"
assert_contains "…naming the seeds there are" "$(<"$TMP_ROOT/err")" "acme"

# --- first copy --------------------------------------------------------------
run_copy acme --root "$ROOT"
assert_eq "first run → exit 0" "0" "$RC"
assert_eq "first run → copied" "copied" "$OUT"
assert_eq "the verb script is copied" "v1" "$(<"$DEST/get-item.sh")"
assert_succeeds "…keeping its executable bit" "executable" "not executable" test -x "$DEST/get-item.sh"
assert_fails "the seed's tests stay in the plugin" "absent" "present" test -e "$DEST/get-item.test.sh"
assert_fails "the seed's mock stays in the plugin" "absent" "present" test -e "$DEST/mock.sh"
assert_fails "the schema check stays in the plugin" "absent" "present" test -e "$DEST/schema-check"
assert_succeeds "the copy records its hash" "present" "absent" test -s "$DEST/.seed-hash"
assert_eq "no staging directory is left behind" "acme" \
  "$(cd "$ROOT/tools/work-item-tracker/adapters" && ls -A)"

run_copy acme --root "$ROOT"
assert_eq "unchanged seed → exit 0" "0" "$RC"
assert_eq "unchanged seed → up-to-date" "up-to-date" "$OUT"

# --- an untouched copy fast-forwards -----------------------------------------
printf 'v2\n' >"$SEEDS/acme/get-item.sh"
printf 'new\n' >"$SEEDS/acme/list-items.sh"
HASH_BEFORE="$(<"$DEST/.seed-hash")"
run_copy acme --root "$ROOT"
assert_eq "changed seed, untouched copy → exit 0" "0" "$RC"
assert_eq "changed seed, untouched copy → fast-forwarded" "fast-forwarded" "$OUT"
assert_eq "the changed file is updated" "v2" "$(<"$DEST/get-item.sh")"
assert_eq "the added file arrives" "new" "$(<"$DEST/list-items.sh")"
if [[ "$(<"$DEST/.seed-hash")" != "$HASH_BEFORE" ]]; then
  pass "the hash record moves to the new seed"
else
  fail "the hash record moves to the new seed" "a new hash" "$HASH_BEFORE"
fi
run_copy acme --root "$ROOT"
assert_eq "after the fast-forward → up-to-date" "up-to-date" "$OUT"

# --- an edited copy stops with a diff ----------------------------------------
printf 'v2\nlocal fix\n' >"$DEST/get-item.sh"
printf 'v3\n' >"$SEEDS/acme/get-item.sh"
run_copy acme --root "$ROOT"
assert_eq "edited copy → exit 1" "1" "$RC"
assert_eq "edited copy → the status line says so" "edited" "$(head -n 1 <<<"$OUT")"
assert_contains "…and the diff shows the local edit" "$OUT" "+local fix"
assert_contains "…against the current seed" "$OUT" "-v3"
assert_eq "the edited file is left as it was" "$(printf 'v2\nlocal fix')" "$(<"$DEST/get-item.sh")"

# A file the consumer added is an edit too: fast-forwarding would delete it.
printf 'v2\n' >"$DEST/get-item.sh"
printf 'v2\n' >"$SEEDS/acme/get-item.sh"
printf 'mine\n' >"$DEST/extra.sh"
run_copy acme --root "$ROOT"
assert_eq "an added file → exit 1" "1" "$RC"
assert_eq "the added file is kept" "mine" "$(<"$DEST/extra.sh")"
rm -f "$DEST/extra.sh"

# A directory with no hash record was not copied from a seed, so it is never replaced.
rm -f "$DEST/.seed-hash"
run_copy acme --root "$ROOT"
assert_eq "no hash record → exit 1" "1" "$RC"
assert_eq "no hash record → edited" "edited" "$(head -n 1 <<<"$OUT")"
assert_fails "…and no record is written" "absent" "present" test -e "$DEST/.seed-hash"

# --- a real seed runs from its copy ------------------------------------------
# The copied jira seed has no ../../lib beside it; the dispatcher's WIT_SEAM_LIB_DIR
# must carry it, through the consumer-local adapter resolution.
JROOT="$TMP_ROOT/jira-repo"
mkdir -p "$JROOT"
OUT="$(bash "$COPY" jira --root "$JROOT" 2>/dev/null)"
assert_eq "the jira seed copies" "copied" "$OUT"
jq -cn '{schema_version:"1.0", provider:"jira",
  config:{lease_ttl_hours:24, jira:{site:"a.atlassian.net", project_keys:["AB"],
    auth_email:"a@example.invalid", auth_env:"WIT_SEED_COPY_TEST_UNUSED"}}}' >"$JROOT/binding.json"
CAPS="$(CLAUDE_PROJECT_DIR="$JROOT" WORK_ITEM_TRACKER_BINDING="$JROOT/binding.json" \
  bash "$TRACKER" capabilities 2>"$TMP_ROOT/err")"
assert_eq "the dispatcher runs the copied jira adapter" "0" "$?"
assert_eq "…which names its provider" "jira" "$(jq -r '.provider' <<<"$CAPS" 2>/dev/null)"

# With no copy the dispatcher points at setup instead of a bare not-found.
rm -rf "$JROOT/tools"
CLAUDE_PROJECT_DIR="$JROOT" WORK_ITEM_TRACKER_BINDING="$JROOT/binding.json" \
  bash "$TRACKER" capabilities >/dev/null 2>"$TMP_ROOT/err"
assert_eq "an uncopied seed → exit 3" "3" "$?"
assert_contains "…naming the setup step that copies it" "$(<"$TMP_ROOT/err")" "/work-items:setup apply"

[[ $FAILED -eq 0 ]] || exit 1
