#!/usr/bin/env bash
# Regression tests for findings-state.sh (self-contained, ships with the plugin).
#
# THE CASE THIS SUITE EXISTS FOR is case 8: two repositories writing the same run
# id into one plugin data root must not collide. That is rule 1 of
# docs/conventions/plugin-data-report-keying/README.md, and an unkeyed
# implementation would serve one project's approved items and evidence to
# another. It is demonstrated with two real git fixtures rather than asserted.
#
# Three cases are NEGATIVE in the sense this repo means it: they mutate a copy of
# the script to delete exactly one check and assert the mutated copy reaches the
# outcome the real one refuses. A test that would still pass with the check
# deleted proves nothing.
#
# File-scoped: `read` is one of findings-state.sh's SUBCOMMAND NAMES, so every
# `run read ...` here is an argument word, never the bash builtin. This suite
# calls the builtin nowhere.
# shellcheck disable=SC2162
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/findings-state.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
assert_file() {
  if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "no such file: $2"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# Every invocation runs with CLAUDE_PLUGIN_ROOT pinned, so a copy of the script
# placed outside the plugin tree still resolves lib/state-key.sh.
run() {
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPT" "$@"
}
run_copy() {
  local copy="$1"
  shift
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$copy" "$@"
}

DATA="$TEST_TMPDIR/plugin-data"
mkdir -p "$DATA"

REPO_A="$TEST_TMPDIR/alpha"
REPO_B="$TEST_TMPDIR/beta"
mkdir -p "$REPO_A" "$REPO_B"
git -C "$REPO_A" init --quiet >/dev/null 2>&1
git -C "$REPO_A" remote add origin https://github.com/example/alpha.git >/dev/null 2>&1
git -C "$REPO_B" init --quiet >/dev/null 2>&1
git -C "$REPO_B" remote add origin https://github.com/example/beta.git >/dev/null 2>&1

GOOD="$TEST_TMPDIR/good.json"
cat >"$GOOD" <<'EOF'
{
  "candidates": [
    {
      "id": "1",
      "candidate": "pre-commit shfmt hook",
      "category": "hooks",
      "verdict": "PASS",
      "evidence": ["shfmt measured at 0.11s", "15% of commits touch shell"],
      "plan": {"files": [".claude/hooks/shfmt.sh"], "effort": "S"},
      "approved": true
    },
    {
      "id": "2",
      "candidate": "database MCP server",
      "category": "mcp",
      "verdict": "REJECT",
      "evidence": ["Premature: no database exists"]
    }
  ],
  "maturity": "One genuine gap."
}
EOF

EMPTY="$TEST_TMPDIR/empty.json"
cat >"$EMPTY" <<'EOF'
{"candidates": [], "maturity": "A clean bill of health."}
EOF

# --- Case 1: --help ---------------------------------------------------------

rc=0
OUT=$(run --help 2>&1) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help names every subcommand" "$OUT" "findings-state.sh list"

# --- Case 2: paths, and the keyed shape it reports --------------------------

rc=0
OUT=$(run paths --plugin-data "$DATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "paths exits 0 on a git target" 0 "$rc"
assert_contains "paths echoes the plugin data dir it was given" "$OUT" "plugin_data=$DATA"
assert_contains "paths derives a state key through lib/state-key.sh" "$OUT" \
  "state_key=github.com/example/alpha/"
assert_contains "the tree is <plugin-data>/<component>/<state-key>" "$OUT" \
  "dir=$DATA/audit-automation-gaps/github.com/example/alpha/"

rc=0
OUT=$(run paths --plugin-data "$DATA" --root "$TEST_TMPDIR" 2>&1) || rc=$?
assert_exit "a non-repository directory still keys" 0 "$rc"
assert_contains "the non-repository rung is used" "$OUT" "state_key=nonrepo/"

# --- Case 3: the missing-plugin-data failure must be LOUD -------------------
#
# ${CLAUDE_PLUGIN_DATA} is not exported to the Bash tool, so the resolved path
# arrives as an argument. Guessing a directory here would write one project's
# verdicts somewhere nothing reads them back.

rc=0
OUT=$(env -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$SCRIPT" paths --root "$REPO_A" 2>&1) || rc=$?
assert_exit "paths exits 2 with no --plugin-data and no exported placeholder" 2 "$rc"
assert_contains "the refusal names why the placeholder is unavailable in Bash" "$OUT" \
  "not exported to the Bash tool"
assert_contains "the refusal names the remedy" "$OUT" "pass the path substituted into the skill text"

rc=0
OUT=$(env -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$SCRIPT" write --root "$REPO_A" --findings "$GOOD" 2>&1) || rc=$?
assert_exit "write exits 2 with no --plugin-data" 2 "$rc"
assert_contains "write's refusal is the same loud one" "$OUT" "not exported to the Bash tool"

rc=0
OUT=$(env -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$SCRIPT" read --root "$REPO_A" 2>&1) || rc=$?
assert_exit "read exits 2 with no --plugin-data" 2 "$rc"

rc=0
OUT=$(env -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$SCRIPT" list --root "$REPO_A" 2>&1) || rc=$?
assert_exit "list exits 2 with no --plugin-data" 2 "$rc"

# An exported value is still honored where one genuinely exists (a hook context).
rc=0
OUT=$(CLAUDE_PLUGIN_DATA="$DATA" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$SCRIPT" paths --root "$REPO_A" 2>&1) || rc=$?
assert_exit "an exported CLAUDE_PLUGIN_DATA is honored where it exists" 0 "$rc"
assert_contains "the exported value is the one used" "$OUT" "plugin_data=$DATA"

rc=0
OUT=$(run paths --plugin-data "relative/dir" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "a relative --plugin-data is refused" 2 "$rc"

rc=0
OUT=$(run paths --plugin-data "/tmp/../etc" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "a --plugin-data containing '..' is refused" 2 "$rc"

# --- Case 4: run-id validation, the path-safety control ---------------------
#
# A run id becomes a filename under the plugin's own tree. lib/state-key.sh
# documents the traversal it defends its half against; this is the other half.

rc=0
OUT=$(run read --plugin-data "$DATA" --root "$REPO_A" --run-id "a..b" 2>&1) || rc=$?
assert_exit "a run id containing '..' is refused" 2 "$rc"
assert_contains "the refusal names the traversal" "$OUT" "must not contain '..'"

rc=0
OUT=$(run read --plugin-data "$DATA" --root "$REPO_A" --run-id "/etc/passwd" 2>&1) || rc=$?
assert_exit "a run id that is not a plain segment is refused" 2 "$rc"

rc=0
OUT=$(run read --plugin-data "$DATA" --root "$REPO_A" --run-id "" 2>&1) || rc=$?
assert_exit "an empty run id is refused" 2 "$rc"

# 4a: NEGATIVE. Delete the '..' arm and the traversal must get through.
BROKEN_DOTS="$TEST_TMPDIR/broken-dots.sh"
sed "/must not contain '\.\.': \$id/s/.*/  *) : ;;/" "$SCRIPT" >"$BROKEN_DOTS"
if grep -qF "must not contain '..': \$id" "$BROKEN_DOTS"; then
  fail "negative traversal case could not be constructed" \
    "the sed target no longer matches findings-state.sh, so the '..' rejection is UNVERIFIED by this run"
else
  rc=0
  broken_out=$(run_copy "$BROKEN_DOTS" read --plugin-data "$DATA" --root "$REPO_A" \
    --run-id "a..b" 2>&1) || rc=$?
  assert_not_contains "with the '..' arm deleted the traversal is no longer refused" \
    "$broken_out" "must not contain"
fi

# --- Case 5: read and list before anything is written -----------------------
#
# Rule 3: an artifact that cannot be attributed to this project is never served,
# and absence is reported rather than papered over with an unkeyed fallback.

rc=0
OUT=$(run read --plugin-data "$DATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "read exits 4 when this project has no artifact" 4 "$rc"
assert_contains "the empty read names the state key it looked under" "$OUT" \
  "github.com/example/alpha/"
assert_contains "the empty read states that nothing outside the key is read" "$OUT" \
  "Nothing outside this key is read"

rc=0
OUT=$(run list --plugin-data "$DATA" --root "$REPO_A" 2>/dev/null) || rc=$?
assert_exit "list exits 0 when this project has no artifact" 0 "$rc"
assert_eq "list prints nothing on stdout when there is nothing" "" "$OUT"

# --- Case 6: write, then read it back ---------------------------------------

rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_A" --run-id run-0001 --findings "$GOOD" 2>&1) || rc=$?
assert_exit "write exits 0 on a conforming payload" 0 "$rc"
assert_contains "write reports the run id it wrote" "$OUT" "run_id=run-0001"
assert_contains "write reports the state key" "$OUT" "state_key=github.com/example/alpha/"
A_KEY=$(run paths --plugin-data "$DATA" --root "$REPO_A" | sed -n 's/^state_key=//p')
A_DIR="$DATA/audit-automation-gaps/$A_KEY"
assert_file "the findings file lands under the keyed tree" "$A_DIR/findings-run-0001.json"
assert_file "the history file is created" "$A_DIR/history.jsonl"
assert_file "the latest pointer is created" "$A_DIR/latest"

rc=0
ENVELOPE=$(run read --plugin-data "$DATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "read exits 0 once a run is persisted" 0 "$rc"
assert_eq "read serves the newest run without a --run-id" "run-0001" \
  "$(printf '%s' "$ENVELOPE" | jq -r '.run_id')"
assert_eq "the envelope carries a schema version" "1" \
  "$(printf '%s' "$ENVELOPE" | jq -r '.schema_version')"
assert_eq "the envelope records the state key it was written under" "$A_KEY" \
  "$(printf '%s' "$ENVELOPE" | jq -r '.state_key')"
assert_eq "counts are derived from the verdict column" "2 1 0 1" \
  "$(printf '%s' "$ENVELOPE" | jq -r '[.counts.total, .counts.pass, .counts.conditional, .counts.reject] | join(" ")')"

# The three payload halves issue #4146 asks to persist: the verdict table, the
# evidence behind each verdict, and the implementation plans.
assert_eq "the verdict table survives the round trip" "PASS REJECT" \
  "$(printf '%s' "$ENVELOPE" | jq -r '[.findings.candidates[].verdict] | join(" ")')"
assert_eq "the evidence survives the round trip" "2" \
  "$(printf '%s' "$ENVELOPE" | jq -r '.findings.candidates[0].evidence | length')"
assert_eq "the implementation plan survives the round trip" ".claude/hooks/shfmt.sh" \
  "$(printf '%s' "$ENVELOPE" | jq -r '.findings.candidates[0].plan.files[0]')"
assert_eq "an approval flag set by the operator survives the round trip" "true" \
  "$(printf '%s' "$ENVELOPE" | jq -r '.findings.candidates[0].approved')"

rc=0
OUT=$(run read --plugin-data "$DATA" --root "$REPO_A" --run-id run-0001 2>&1) || rc=$?
assert_exit "read accepts an explicit --run-id" 0 "$rc"

rc=0
OUT=$(run read --plugin-data "$DATA" --root "$REPO_A" --run-id no-such-run 2>&1) || rc=$?
assert_exit "read exits 4 for a run id with no file" 4 "$rc"

# --- Case 7: stdin, the default run id, and non-overwrite -------------------

rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_A" --findings - <"$EMPTY" 2>&1) || rc=$?
assert_exit "write accepts the payload on stdin" 0 "$rc"
assert_contains "the default run id is a UTC timestamp" "$OUT" "run_id=20"

rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_A" --run-id run-0001 --findings "$EMPTY" 2>&1) || rc=$?
assert_exit "a colliding run id still writes" 0 "$rc"
assert_contains "a colliding run id is suffixed rather than overwritten" "$OUT" "run_id=run-0001-2"
assert_eq "the first run's verdicts are untouched" "2" \
  "$(jq -r '.counts.total' "$A_DIR/findings-run-0001.json")"

rc=0
OUT=$(run list --plugin-data "$DATA" --root "$REPO_A" 2>/dev/null) || rc=$?
assert_exit "list exits 0" 0 "$rc"
assert_eq "list prints one JSON line per persisted run" "3" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert_eq "every history line parses as JSON" "3" \
  "$(printf '%s\n' "$OUT" | jq -s 'length')"
assert_eq "the newest run is last" "run-0001-2" \
  "$(printf '%s\n' "$OUT" | jq -s -r '.[-1].run_id')"

# --- Case 8: THE COLLISION PROOF --------------------------------------------
#
# Two repositories, one plugin data root, the SAME run id, different payloads.
# Under an unkeyed layout the second write replaces the first and the first
# project is then served the second's approved items.

rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_B" --run-id run-0001 --findings "$EMPTY" 2>&1) || rc=$?
assert_exit "repo B writes the same run id without error" 0 "$rc"
B_KEY=$(run paths --plugin-data "$DATA" --root "$REPO_B" | sed -n 's/^state_key=//p')
if [[ "$A_KEY" != "$B_KEY" ]]; then
  pass "two repositories derive different state keys"
else
  fail "two repositories derive different state keys" "both derived: $A_KEY"
fi
assert_file "repo B's findings file is a separate path" \
  "$DATA/audit-automation-gaps/$B_KEY/findings-run-0001.json"
assert_eq "repo A still serves ITS OWN verdict count" "2" \
  "$(run read --plugin-data "$DATA" --root "$REPO_A" --run-id run-0001 | jq -r '.counts.total')"
assert_eq "repo B still serves ITS OWN verdict count" "0" \
  "$(run read --plugin-data "$DATA" --root "$REPO_B" --run-id run-0001 | jq -r '.counts.total')"
assert_eq "repo B's history holds only its own run" "1" \
  "$(run list --plugin-data "$DATA" --root "$REPO_B" 2>/dev/null | wc -l | tr -d ' ')"

# 8a: NEGATIVE. Drop the state key out of the path and the two collide.
BROKEN_KEY="$TEST_TMPDIR/broken-key.sh"
# shellcheck disable=SC2016 # sed program text: the $ are literal characters in the script being mutated
sed 's|BASE_DIR="\$PLUGIN_DATA/\$COMPONENT/\$STATE_KEY"|BASE_DIR="$PLUGIN_DATA/$COMPONENT"|' \
  "$SCRIPT" >"$BROKEN_KEY"
# shellcheck disable=SC2016 # grep pattern text: same literal $ as the sed above
if grep -q 'BASE_DIR="\$PLUGIN_DATA/\$COMPONENT/\$STATE_KEY"' "$BROKEN_KEY"; then
  fail "negative keying case could not be constructed" \
    "the sed target no longer matches findings-state.sh, so the keying is UNVERIFIED by this run"
else
  UNKEYED="$TEST_TMPDIR/unkeyed-data"
  mkdir -p "$UNKEYED"
  run_copy "$BROKEN_KEY" write --plugin-data "$UNKEYED" --root "$REPO_A" \
    --run-id shared --findings "$GOOD" >/dev/null 2>&1
  run_copy "$BROKEN_KEY" write --plugin-data "$UNKEYED" --root "$REPO_B" \
    --run-id shared --findings "$EMPTY" >/dev/null 2>&1
  # Repo B's write landed beside repo A's under one unkeyed directory, so repo A
  # is now served an artifact it did not produce: the `latest` pointer names
  # repo B's run.
  broken_latest=$(run_copy "$BROKEN_KEY" read --plugin-data "$UNKEYED" --root "$REPO_A" |
    jq -r '.state_key')
  assert_eq "with the state key deleted, repo A is served repo B's artifact" \
    "$B_KEY" "$broken_latest"
fi

# --- Case 9: payload rejection ----------------------------------------------

BAD="$TEST_TMPDIR/bad.json"
cat >"$BAD" <<'EOF'
{
  "candidates": [
    {"id": "1", "candidate": "x", "category": "githooks", "verdict": "PASS", "evidence": ["e"]},
    {"id": "2", "category": "hooks", "verdict": "MAYBE", "evidence": "not an array"}
  ]
}
EOF

before=$(find "$A_DIR" -name 'findings-*.json' | wc -l | tr -d ' ')
rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_A" --run-id rejected --findings "$BAD" 2>&1) || rc=$?
assert_exit "a non-conforming payload exits 3" 3 "$rc"
assert_contains "an unknown category is named" "$OUT" '"category" must be one of'
assert_contains "an unknown verdict is named" "$OUT" '"verdict" must be one of'
assert_contains "a missing field is named" "$OUT" 'missing required field "candidate"'
assert_contains "evidence of the wrong type is named" "$OUT" '"evidence" must be an array of strings'
assert_contains "a PASS with no plan is named" "$OUT" 'must carry a "plan" object'
after=$(find "$A_DIR" -name 'findings-*.json' | wc -l | tr -d ' ')
assert_eq "a rejected payload writes no findings file" "$before" "$after"
assert_eq "a rejected payload leaves no staged temporary behind" "0" \
  "$(find "$A_DIR" -name '.payload.*' -o -name '.envelope.*' | wc -l | tr -d ' ')"

rc=0
OUT=$(printf 'not json at all' | run write --plugin-data "$DATA" --root "$REPO_A" --findings - 2>&1) || rc=$?
assert_exit "a payload that is not JSON exits 3" 3 "$rc"
assert_contains "the refusal says the payload is not well-formed JSON" "$OUT" "not well-formed JSON"

rc=0
OUT=$(printf '[1,2,3]' | run write --plugin-data "$DATA" --root "$REPO_A" --findings - 2>&1) || rc=$?
assert_exit "a JSON array payload exits 3" 3 "$rc"
assert_contains "the refusal says the payload must be an object" "$OUT" "must be a JSON object"

rc=0
OUT=$(printf '{"maturity":"none"}' | run write --plugin-data "$DATA" --root "$REPO_A" --findings - 2>&1) || rc=$?
assert_exit "a payload with no candidates key exits 3" 3 "$rc"
assert_contains "the refusal names the missing verdict table" "$OUT" 'must carry a "candidates" array'

# An empty verdict table is a RESULT, not a rejection: the skill's own quality
# principles make a clean bill of health a valid outcome.
rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_B" --run-id clean --findings "$EMPTY" 2>&1) || rc=$?
assert_exit "an empty candidates array is accepted" 0 "$rc"

# 9a: the plan requirement, and its NEGATIVE. A PASS with no plan is the state
# that leaves --implement holding a verdict and nothing to act on.
NO_PLAN="$TEST_TMPDIR/no-plan.json"
cat >"$NO_PLAN" <<'EOF'
{"candidates": [{"id":"1","candidate":"x","category":"hooks","verdict":"PASS","evidence":["e"]}]}
EOF
rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_A" --run-id noplan --findings "$NO_PLAN" 2>&1) || rc=$?
assert_exit "a PASS with no plan is refused" 3 "$rc"

BROKEN_PLAN="$TEST_TMPDIR/broken-plan.sh"
sed 's@c.plan | type) != "object"@c.plan | type) == "object"@' "$SCRIPT" >"$BROKEN_PLAN"
if grep -qF 'c.plan | type) != "object"' "$BROKEN_PLAN"; then
  fail "negative plan-requirement case could not be constructed" \
    "the sed target no longer matches findings-state.sh, so the plan requirement is UNVERIFIED by this run"
else
  rc=0
  run_copy "$BROKEN_PLAN" write --plugin-data "$DATA" --root "$REPO_A" \
    --run-id noplan-broken --findings "$NO_PLAN" >/dev/null 2>&1 || rc=$?
  assert_exit "with the plan requirement inverted, a PASS with no plan is accepted" 0 "$rc"
fi

# --- Case 10: argument surface ----------------------------------------------

rc=0
OUT=$(run 2>&1) || rc=$?
assert_exit "no command exits 2" 2 "$rc"

rc=0
OUT=$(run bogus 2>&1) || rc=$?
assert_exit "an unknown command exits 2" 2 "$rc"
assert_contains "the refusal names the command" "$OUT" "unknown command: bogus"

rc=0
OUT=$(run paths --plugin-data "$DATA" --bogus x 2>&1) || rc=$?
assert_exit "an unknown argument exits 2" 2 "$rc"

rc=0
OUT=$(run paths --plugin-data "$DATA" --run-id x 2>&1) || rc=$?
assert_exit "paths refuses --run-id" 2 "$rc"

rc=0
OUT=$(run list --plugin-data "$DATA" --findings "$GOOD" 2>&1) || rc=$?
assert_exit "list refuses --findings" 2 "$rc"

rc=0
OUT=$(run read --plugin-data "$DATA" --findings "$GOOD" 2>&1) || rc=$?
assert_exit "read refuses --findings" 2 "$rc"

rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "write with no --findings exits 2" 2 "$rc"

rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_A" --findings "$TEST_TMPDIR/nope.json" 2>&1) || rc=$?
assert_exit "write with a missing payload file exits 2" 2 "$rc"

rc=0
OUT=$(run paths --plugin-data "$DATA" --root "$TEST_TMPDIR/not-there" 2>&1) || rc=$?
assert_exit "a --root that is not a directory exits 2" 2 "$rc"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
