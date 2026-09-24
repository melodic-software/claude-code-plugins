#!/usr/bin/env bash
# Tests for ratchet.py, the counter-ceiling check /performance:protect wires
# into CI.
#
# The behavior under test is the exit split: 0 at or below every ceiling, 1 a
# counter above one, 2 a ratchet that could not measure. A ratchet that reads a
# failed command or a missing field as a pass protects nothing, so every way the
# measurement can fail is driven here and must exit 2, never 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
RATCHET="$SCRIPT_DIR/ratchet.py"
readonly RATCHET

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT

# ceilings <file> <command> <ceiling>: one counter reading field `spawns`.
ceilings() {
  "$HARNESS_PYTHON" -c 'import json, sys
json.dump({"counters": [{"name": "hook", "command": sys.argv[2], "field": "spawns",
  "ceiling": int(sys.argv[3]), "goal": "hook stays at one spawn"}]}, open(sys.argv[1], "w"))' \
    "$1" "$2" "$3"
}

ratchet() { capture "$HARNESS_PYTHON" "$RATCHET" "$@"; }

F="$WORK/r.json"

# --- 1. below, at, and above the ceiling ---
ceilings "$F" 'echo "hook spawns=3 rc=0"' 4
ratchet check --file "$F"
assert_eq "below the ceiling exits 0" "0" "$RUN_RC"
assert_contains "below the ceiling offers to tighten" "propose-tighten can lower it" "$RUN_OUT"

ceilings "$F" 'echo "hook spawns=4 rc=0"' 4
ratchet check --file "$F"
assert_eq "at the ceiling exits 0" "0" "$RUN_RC"

# The negative control the whole ratchet exists for.
ceilings "$F" 'echo "hook spawns=5 rc=0"' 4
ratchet check --file "$F"
assert_eq "above the ceiling exits 1" "1" "$RUN_RC"
assert_contains "the regression names the counter and both numbers" \
  "ABOVE  hook: spawns=5 > ceiling 4" "$RUN_OUT"

# --- 2. every failed measurement exits 2, never 0 ---
printf '{"counters": [' >"$F"
ratchet check --file "$F"
assert_eq "malformed JSON is refused" "2" "$RUN_RC"
assert_contains "the refusal says why" "not valid JSON" "$RUN_OUT"

printf '{"counters": [{"name": "hook", "command": "true", "field": "spawns", "ceilling": 4, "goal": "g"}]}' >"$F"
ratchet check --file "$F"
assert_eq "a misspelled key is refused, not read as no ceiling" "2" "$RUN_RC"

printf '{"counters": [{"name": "hook", "command": "true", "field": "spawns", "ceiling": true, "goal": "g"}]}' >"$F"
ratchet check --file "$F"
assert_eq "a boolean ceiling is refused" "2" "$RUN_RC"

ceilings "$F" 'echo "hook calls=3 rc=0"' 4
ratchet check --file "$F"
assert_eq "a missing field is refused" "2" "$RUN_RC"
assert_contains "the refusal names the field" "no numeric spawns=<number>" "$RUN_OUT"

ceilings "$F" 'echo "hook spawns=many"' 4
ratchet check --file "$F"
assert_eq "a non-numeric field is refused" "2" "$RUN_RC"

# A failing command that still printed a low count is the false green: the
# subject never ran, and its number is below every ceiling.
ceilings "$F" 'echo "hook spawns=0"; exit 3' 4
ratchet check --file "$F"
assert_eq "a failed command is refused even when it printed a count" "2" "$RUN_RC"
assert_contains "the refusal names the exit status" "exited 3" "$RUN_OUT"

printf '{"counters": []}' >"$F"
ratchet check --file "$F"
assert_eq "a check over no counters is refused, not passed" "2" "$RUN_RC"

ratchet check --file "$WORK/absent.json"
assert_eq "a missing ceilings file is refused" "2" "$RUN_RC"

# --- 3. propose-tighten lowers only with --write, and never past a regression ---
ceilings "$F" 'echo "hook spawns=2"' 4
ratchet propose-tighten --file "$F"
assert_eq "a dry run exits 0" "0" "$RUN_RC"
assert_contains "the dry run prints the new ceiling" "TIGHTEN hook: ceiling 4 -> 2" "$RUN_OUT"
assert_contains "the dry run leaves the file alone" '"ceiling": 4' "$(<"$F")"

ratchet propose-tighten --file "$F" --write
assert_eq "--write exits 0" "0" "$RUN_RC"
assert_contains "--write records the lower ceiling" '"ceiling": 2' "$(<"$F")"

ratchet propose-tighten --file "$F"
assert_contains "at the ceiling there is nothing to tighten" "no ceiling can tighten" "$RUN_OUT"

ceilings "$F" 'echo "hook spawns=9"' 4
ratchet propose-tighten --file "$F" --write
assert_eq "propose-tighten over a regression exits 1" "1" "$RUN_RC"
assert_contains "a regression blocks the write" '"ceiling": 4' "$(<"$F")"

DIP="$WORK/dip"
ceilings "$F" "n=\$(cat '$DIP' 2>/dev/null || echo 2); echo \$((n + 1)) >'$DIP'; echo spawns=\$n" 4
ratchet propose-tighten --file "$F" --write
assert_eq "a dip the second run does not repeat is refused" "2" "$RUN_RC"
assert_contains "a one-run dip never lowers the ceiling" '"ceiling": 4' "$(<"$F")"

printf '{"counters": []}' >"$F"
ratchet propose-tighten --file "$F"
assert_eq "propose-tighten over no counters is refused" "2" "$RUN_RC"

# --- 4. add measures twice and records the agreed value ---
A="$WORK/new-dir/added.json"
ratchet add --file "$A" --name hook --field spawns --goal "one spawn" --command 'echo "spawns=1"'
assert_eq "add creates a missing file" "0" "$RUN_RC"
assert_contains "add records the measured value as the ceiling" '"ceiling": 1' "$(<"$A")"
ratchet check --file "$A"
assert_eq "the added counter passes its own check" "0" "$RUN_RC"

ratchet add --file "$A" --name hook --field spawns --goal "g" --command 'echo "spawns=1"'
assert_eq "a duplicate name is refused" "2" "$RUN_RC"

# A counter that moves between two runs of an unchanged subject.
COUNT="$WORK/count"
ratchet add --file "$A" --name drifts --field spawns --goal "g" \
  --command "n=\$(cat '$COUNT' 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n >'$COUNT'; echo spawns=\$n"
assert_eq "a counter that disagrees with itself is refused" "2" "$RUN_RC"
assert_contains "the refusal shows both runs" "measured 1 then 2" "$RUN_OUT"
assert_not_contains "nothing is recorded for it" "drifts" "$(<"$A")"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: ratchet ceilings"
exit 0
