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

# A NaN ceiling compares false both ways, so every count would read as equal.
for bad in NaN Infinity -Infinity; do
  printf '{"counters": [{"name": "hook", "command": "echo spawns=999", "field": "spawns", "ceiling": %s, "goal": "g"}]}' "$bad" >"$F"
  ratchet check --file "$F"
  assert_eq "a $bad ceiling is refused" "2" "$RUN_RC"
done

# 400 digits parse to float inf, which no ceiling can hold.
ceilings "$F" "echo spawns=$(printf '9%.0s' {1..400}).0" 4
ratchet check --file "$F"
assert_eq "a non-finite measured value is refused" "2" "$RUN_RC"
assert_contains "the refusal says not finite" "not a finite number" "$RUN_OUT"

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

# --- 5. --runs sets how many agreeing runs add and propose-tighten need ---
# tally <file>: a command that counts its own runs in <file> and prints spawns=1.
tally() { printf "n=\$(cat '%s' 2>/dev/null || echo 0); echo \$((n + 1)) >'%s'; echo spawns=1" "$1" "$1"; }

R="$WORK/runs.json"
ratchet add --file "$R" --name twice --field spawns --goal "g" --command "$(tally "$WORK/t2")"
assert_eq "add without --runs exits 0" "0" "$RUN_RC"
assert_eq "add without --runs measures twice" "2" "$(<"$WORK/t2")"

ratchet add --file "$R" --name once --field spawns --goal "g" --runs 1 --command "$(tally "$WORK/t1")"
assert_eq "add --runs 1 exits 0" "0" "$RUN_RC"
assert_eq "add --runs 1 measures once" "1" "$(<"$WORK/t1")"

# Runs one and two agree on 1; run three reads 2.
THIRD="$WORK/third"
ratchet add --file "$R" --name late --field spawns --goal "g" --runs 3 \
  --command "n=\$(cat '$THIRD' 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n >'$THIRD'; echo spawns=\$((n / 3 + 1))"
assert_eq "add --runs 3 refuses a disagreement on the third run" "2" "$RUN_RC"
assert_contains "the refusal shows all three runs" "measured 1 then 1 then 2" "$RUN_OUT"
assert_not_contains "nothing is recorded for it" "late" "$(<"$R")"

for bad in 0 -1; do
  ratchet add --file "$R" --name zero --field spawns --goal "g" --runs "$bad" --command 'echo spawns=1'
  assert_eq "add --runs $bad is refused" "2" "$RUN_RC"
  assert_contains "the --runs $bad refusal states the minimum" "at least 1" "$RUN_OUT"
done

# One run accepts the dip that two runs refuse above.
ceilings "$F" "n=\$(cat '$WORK/dip1' 2>/dev/null || echo 2); echo \$((n + 1)) >'$WORK/dip1'; echo spawns=\$n" 4
ratchet propose-tighten --file "$F" --write --runs 1
assert_eq "propose-tighten --runs 1 exits 0" "0" "$RUN_RC"
assert_contains "propose-tighten --runs 1 records the one-run value" '"ceiling": 2' "$(<"$F")"

ratchet propose-tighten --file "$F" --runs 0
assert_eq "propose-tighten --runs 0 is refused" "2" "$RUN_RC"
assert_contains "the propose-tighten refusal states the minimum" "at least 1" "$RUN_OUT"

# --- 6. per-file ceilings: a fix in one file never pays for a new violation in another ---
# per_file <file> <command> <ceilings-json> [break_glass]: one per-file counter reading `violations`.
per_file() {
  "$HARNESS_PYTHON" -c 'import json, sys
data = {"counters": [{"name": "lint", "command": sys.argv[2], "field": "violations",
  "ceilings": json.loads(sys.argv[3]), "goal": "no new lint violations"}]}
if len(sys.argv) > 4: data["break_glass"] = sys.argv[4] == "true"
json.dump(data, open(sys.argv[1], "w"))' "$@"
}

P="$WORK/per-file.json"
A_SRC="$WORK/a.ts"
B_SRC="$WORK/b.ts"
: >"$A_SRC"
: >"$B_SRC"

# File a falls from 3 to 1 while file b gains one: the total falls from 3 to 2.
per_file "$P" "printf '%s violations=1\n%s violations=1\n' '$A_SRC' '$B_SRC'" "{\"$A_SRC\": 3}"
ratchet check --file "$P"
assert_eq "a new violation in file b fails though the total fell" "1" "$RUN_RC"
assert_contains "the failure names file b" "ABOVE  lint: $B_SRC violations=1 > ceiling 0" "$RUN_OUT"
assert_not_contains "file a below its ceiling is not named as above" "ABOVE  lint: $A_SRC" "$RUN_OUT"

per_file "$P" "printf '%s violations=2\n' '$A_SRC'" "{\"$A_SRC\": 3}"
ratchet check --file "$P"
assert_eq "every file at or below its ceiling exits 0" "0" "$RUN_RC"
assert_contains "the pass offers to tighten" "propose-tighten can lower 1" "$RUN_OUT"

per_file "$P" "echo 'garbage line'" "{}"
ratchet check --file "$P"
assert_eq "a line that is not '<path> <field>=<n>' is refused" "2" "$RUN_RC"

per_file "$P" "printf '%s violations=1\n%s violations=1\n' '$A_SRC' '$A_SRC'" "{}"
ratchet check --file "$P"
assert_eq "a file printed twice is refused" "2" "$RUN_RC"

per_file "$P" "true" "{\"$A_SRC\": -1}"
ratchet check --file "$P"
assert_eq "a negative file ceiling is refused" "2" "$RUN_RC"

# propose-tighten lowers file ceilings and drops a file that reached 0.
per_file "$P" "printf '%s violations=1\n' '$A_SRC'" "{\"$A_SRC\": 3, \"$B_SRC\": 2}"
ratchet propose-tighten --file "$P" --write
assert_eq "per-file propose-tighten exits 0" "0" "$RUN_RC"
assert_contains "the lowered file ceiling is recorded" "\"$A_SRC\": 1" "$(<"$P")"
assert_not_contains "a file at 0 leaves the ceilings" "$B_SRC" "$(<"$P")"

per_file "$P" "printf '%s violations=1\n%s violations=1\n' '$A_SRC' '$B_SRC'" "{\"$A_SRC\": 3}"
ratchet propose-tighten --file "$P" --write
assert_eq "per-file propose-tighten over a new file's violation exits 1" "1" "$RUN_RC"
assert_contains "the regression blocks the write" "\"$A_SRC\": 3" "$(<"$P")"

PA="$WORK/per-file-added.json"
ratchet add --file "$PA" --per-file --break-glass off --name lint --field violations --goal "g" \
  --command "printf '%s violations=2\n%s violations=0\n' '$A_SRC' '$B_SRC'"
assert_eq "add --per-file exits 0" "0" "$RUN_RC"
assert_contains "add --per-file records a ceiling per file" "\"$A_SRC\": 2" "$(<"$PA")"
assert_not_contains "a file at 0 gets no ceiling" "\"$B_SRC\": 0" "$(<"$PA")"
assert_contains "add --break-glass records the setting" '"break_glass": false' "$(<"$PA")"

# --- 7. break glass: an inline exception with a reason, an expiry and an approver ---
OVER="printf '%s violations=1\n' '$B_SRC'"
VALID="// ratchet-break-glass(lint): reason=vendor bug; expires=2999-01-01; approved-by=alice"

printf '%s\n' "$VALID" >"$B_SRC"
per_file "$P" "$OVER" "{}" true
ratchet check --file "$P"
assert_eq "a valid exception holds a file one above its ceiling" "0" "$RUN_RC"
assert_contains "the held file is reported" "EXCEPT lint: $B_SRC" "$RUN_OUT"

per_file "$P" "$OVER" "{}" false
ratchet check --file "$P"
assert_eq "with break glass off the exception is not read" "1" "$RUN_RC"

per_file "$P" "$OVER" "{}"
ratchet check --file "$P"
assert_eq "with break glass absent the exception is not read" "1" "$RUN_RC"

per_file "$P" "printf '%s violations=2\n' '$B_SRC'" "{}" true
ratchet check --file "$P"
assert_eq "one exception holds one violation, not two" "1" "$RUN_RC"

for bad in "reason=x; expires=2999-01-01" "reason=x; approved-by=alice" \
  "expires=2999-01-01; approved-by=alice" "reason=x; expires=soon; approved-by=alice"; do
  printf '# ratchet-break-glass(lint): %s\n' "$bad" >"$B_SRC"
  per_file "$P" "$OVER" "{}" true
  ratchet check --file "$P"
  assert_eq "an exception with '$bad' fails the check" "1" "$RUN_RC"
  assert_contains "the failure names the exception" "BROKEN lint: break-glass exception at $B_SRC:1" "$RUN_OUT"
done

printf '%s\n' "// ratchet-break-glass(lint): reason=x; expires=2000-01-01; approved-by=alice" >"$B_SRC"
per_file "$P" "$OVER" "{}" true
ratchet check --file "$P"
assert_eq "an expired exception fails the check" "1" "$RUN_RC"
assert_contains "the failure says it expired" "expired 2000-01-01" "$RUN_OUT"

# A malformed exception fails even in a file at its ceiling.
printf '%s\n' "/* ratchet-break-glass(lint): reason=x */" >"$B_SRC"
per_file "$P" "printf '%s violations=0\n' '$B_SRC'" "{}" true
ratchet check --file "$P"
assert_eq "a malformed exception in a file at its ceiling fails" "1" "$RUN_RC"

printf '%s\n' "// ratchet-break-glass(other): reason=x; expires=2999-01-01; approved-by=alice" >"$B_SRC"
per_file "$P" "$OVER" "{}" true
ratchet check --file "$P"
assert_eq "an exception for another counter holds nothing" "1" "$RUN_RC"

per_file "$P" "true" "{}"
"$HARNESS_PYTHON" -c 'import json, sys
data = json.load(open(sys.argv[1])); data["break_glass"] = "yes"; json.dump(data, open(sys.argv[1], "w"))' "$P"
ratchet check --file "$P"
assert_eq "a non-boolean break_glass is refused" "2" "$RUN_RC"
assert_contains "the refusal names the key" '"break_glass" must be true or false' "$RUN_OUT"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: ratchet ceilings"
exit 0
