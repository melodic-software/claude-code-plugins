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
SKIPPED=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
# A host-capability skip is reported as itself and never through pass(), so a
# proof this host could not run can never be read off the summary as one that
# did.
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
}
# Under MSYS without winsymlinks, `ln -s` COPIES the target instead of linking
# it. Two cases below need a real symlink: one plants a dangling link to make an
# append fail, the other plants a link to prove the pointer is replaced rather
# than written through. Probe the round trip rather than the OS name.
host_makes_symlinks() {
  local d rc=1
  d="$(mktemp -d)"
  printf 'x\n' >"$d/target"
  if ln -s target "$d/link" 2>/dev/null &&
    [[ -L "$d/link" ]] && [[ "$(readlink "$d/link" 2>/dev/null)" == "target" ]]; then
    rc=0
  fi
  rm -rf "$d"
  return "$rc"
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

# A DIRECTORY may legitimately be named `a..b`; a run id may not. The two rules
# differ on purpose, and each message says which rule it is enforcing.
mkdir -p "$TEST_TMPDIR/a..b/data"
rc=0
OUT=$(run paths --plugin-data "$TEST_TMPDIR/a..b/data" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "a real directory named a..b keys like any other" 0 "$rc"
assert_contains "the a..b directory is the one used" "$OUT" "plugin_data=$TEST_TMPDIR/a..b/data"

rc=0
OUT=$(run paths --plugin-data "$TEST_TMPDIR/../etc" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "a real '..' path component is still refused" 2 "$rc"
assert_contains "the refusal names the component, not a substring" "$OUT" \
  "must not contain a '..' path component"

# 4a: NEGATIVE. Delete the '..' arm and the dot-run id must reach the filename it
# would become. Asserting only that a message disappears would also pass if the
# id were refused a line later for some unrelated reason; the constructed path in
# the output is what shows the id actually got through to path construction.
DOTS_DATA="$TEST_TMPDIR/dots-data"
mkdir -p "$DOTS_DATA"
DOTS_KEY=$(run paths --plugin-data "$DOTS_DATA" --root "$REPO_A" | sed -n 's/^state_key=//p')
mkdir -p "$DOTS_DATA/audit-automation-gaps/$DOTS_KEY"
BROKEN_DOTS="$TEST_TMPDIR/broken-dots.sh"
sed "/must not contain '\.\.': \$id/s/.*/  *) : ;;/" "$SCRIPT" >"$BROKEN_DOTS"
if grep -qF "must not contain '..': \$id" "$BROKEN_DOTS"; then
  fail "negative traversal case could not be constructed" \
    "the sed target no longer matches findings-state.sh, so the '..' rejection is UNVERIFIED by this run"
else
  rc=0
  broken_out=$(run_copy "$BROKEN_DOTS" read --plugin-data "$DOTS_DATA" --root "$REPO_A" \
    --run-id "a..b" 2>&1) || rc=$?
  assert_not_contains "with the '..' arm deleted the dot run is no longer refused" \
    "$broken_out" "must not contain"
  assert_exit "with the arm deleted the id reaches the artifact lookup instead" 4 "$rc"
  assert_contains "and it reaches it as a FILENAME built from the dot run" \
    "$broken_out" "findings-a..b.json"
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

# The three payload parts this store exists to persist: the verdict table, the
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

# --- Case 11: CONCURRENCY, the never-overwritten promise under a real race ----
#
# Five writers, ONE run id, five DISTINCT payloads, all in flight at once. A
# check-then-publish implementation passes every earlier case in this file and
# still loses four verdict sets here while reporting success five times, which is
# the worst thing a persistence layer can do. The claim under test is not "it
# does not crash": it is that every payload that was reported written is on disk
# under the id that was reported back.

CDATA="$TEST_TMPDIR/concurrent-data"
mkdir -p "$CDATA"
for i in 1 2 3 4 5; do
  printf '{"candidates":[{"id":"%s","candidate":"c%s","category":"hooks","verdict":"REJECT","evidence":["e%s"]}]}\n' \
    "$i" "$i" "$i" >"$TEST_TMPDIR/conc-$i.json"
done
for i in 1 2 3 4 5; do
  run write --plugin-data "$CDATA" --root "$REPO_A" --run-id shared \
    --findings "$TEST_TMPDIR/conc-$i.json" >"$TEST_TMPDIR/conc-out-$i" 2>&1 &
done
wait
CONC_DIR="$CDATA/audit-automation-gaps/$A_KEY"
assert_eq "five concurrent writes leave five findings files" "5" \
  "$(find "$CONC_DIR" -name 'findings-shared*.json' | wc -l | tr -d ' ')"
CONC_IDS=$(cat "$TEST_TMPDIR"/conc-out-* | sed -n 's/^run_id=//p' | sort)
assert_eq "each concurrent write reports a DISTINCT run id" "5" \
  "$(printf '%s\n' "$CONC_IDS" | sort -u | wc -l | tr -d ' ')"
assert_eq "the suffixes are the documented ones" "shared shared-2 shared-3 shared-4 shared-5" \
  "$(printf '%s\n' "$CONC_IDS" | tr '\n' ' ' | sed 's/ *$//')"
conc_missing=""
for id in $CONC_IDS; do
  if [[ ! -f "$CONC_DIR/findings-$id.json" ]]; then
    conc_missing="$conc_missing $id"
  fi
done
assert_eq "every run id reported back names a file that exists" "" "$conc_missing"
assert_eq "every payload survives, none overwritten by another writer" "1 2 3 4 5" \
  "$(cat "$CONC_DIR"/findings-shared*.json | jq -r '.findings.candidates[0].id' | sort | tr '\n' ' ' | sed 's/ *$//')"
assert_eq "the history carries one row per surviving run, not five claiming one id" "5" \
  "$(jq -r '.run_id' <"$CONC_DIR/history.jsonl" | sort -u | wc -l | tr -d ' ')"
assert_eq "read serves a real per-run file after the race" "1" \
  "$(run read --plugin-data "$CDATA" --root "$REPO_A" | jq -r '.findings.candidates | length')"

# --- Case 12: one payload document, because only one can be persisted ---------
#
# jq accepts a stream of concatenated documents, so a two-document payload used
# to validate in full and persist only the first. A stream whose second half
# holds the real verdicts then reported success with counts of zero.

MULTI="$TEST_TMPDIR/multi.json"
cat >"$MULTI" <<'EOF'
{"candidates": [], "maturity": "a clean bill of health"}
{"candidates": [{"id":"9","candidate":"real gap","category":"hooks","verdict":"REJECT","evidence":["real evidence"]}]}
EOF
rc=0
OUT=$(run write --plugin-data "$DATA" --root "$REPO_A" --run-id multi --findings "$MULTI" 2>&1) || rc=$?
assert_exit "a multi-document payload exits 3" 3 "$rc"
assert_contains "the refusal names the one-document rule" "$OUT" "exactly one JSON document"
assert_contains "the refusal says which half would have been kept" "$OUT" \
  "only the first document would be persisted"
assert_eq "a multi-document payload writes no findings file" "" \
  "$(find "$A_DIR" -name 'findings-multi*.json')"

# --- Case 13: a publish is all or nothing, and an orphan is not an absence ----

ODATA="$TEST_TMPDIR/orphan-data"
ODIR="$ODATA/audit-automation-gaps/$A_KEY"
mkdir -p "$ODIR/history.jsonl"
rc=0
OUT=$(run write --plugin-data "$ODATA" --root "$REPO_A" --run-id h1 --findings "$GOOD" 2>&1) || rc=$?
assert_exit "write refuses up front when the history file cannot be appended to" 5 "$rc"
assert_contains "the refusal says nothing was written" "$OUT" "nothing was written"
assert_eq "and nothing was: no orphan findings file is left on disk" "" \
  "$(find "$ODIR" -name 'findings-*.json')"

# A findings file whose pointers are gone is an INCOMPLETE PUBLISH. Reporting it
# as "no findings are persisted" denies a verdict set that is sitting on disk.
PDATA="$TEST_TMPDIR/partial-data"
mkdir -p "$PDATA"
run write --plugin-data "$PDATA" --root "$REPO_A" --run-id partial --findings "$GOOD" >/dev/null 2>&1
PDIR="$PDATA/audit-automation-gaps/$A_KEY"
rm -f "$PDIR/latest" "$PDIR/history.jsonl"
rc=0
OUT=$(run read --plugin-data "$PDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "read reports an orphaned findings file rather than absence" 5 "$rc"
assert_contains "the report names the incomplete publish" "$OUT" "INCOMPLETE PUBLISH"
assert_contains "the report names the file the operator can still read" "$OUT" "findings-partial.json"
assert_not_contains "and does not claim nothing is persisted" "$OUT" "no findings are persisted"
rc=0
OUT=$(run list --plugin-data "$PDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "list reports the orphan rather than an empty listing" 5 "$rc"
assert_not_contains "list does not call an incomplete publish 'no persisted runs'" "$OUT" \
  "no persisted runs"
rc=0
OUT=$(run read --plugin-data "$PDATA" --root "$REPO_A" --run-id partial 2>&1) || rc=$?
assert_exit "the orphaned run is still readable by its id" 0 "$rc"

# The pre-flight cannot see every failure, so the publish is also rolled back
# when the append fails anyway. A DANGLING symlink is the reproduction: `-e` is
# false for one, so it passes the pre-flight, and the append into a directory
# that does not exist then fails with the findings file already published.
if host_makes_symlinks; then
  RBDATA="$TEST_TMPDIR/rollback-data"
  RBDIR="$RBDATA/audit-automation-gaps/$A_KEY"
  mkdir -p "$RBDIR"
  ln -s "$RBDIR/no-such-dir/history.jsonl" "$RBDIR/history.jsonl"
  rc=0
  OUT=$(run write --plugin-data "$RBDATA" --root "$REPO_A" --run-id rb --findings "$GOOD" 2>&1) || rc=$?
  assert_exit "a failed history append is reported as unusable state, not a usage error" 5 "$rc"
  assert_contains "the report says the findings file was rolled back" "$OUT" "rolled back"
  assert_eq "the published findings file is rolled back rather than orphaned" "" \
    "$(find "$RBDIR" -name 'findings-rb*.json')"
  rc=0
  OUT=$(run read --plugin-data "$RBDATA" --root "$REPO_A" 2>&1) || rc=$?
  assert_exit "and the rolled-back run leaves no orphan for read to report" 4 "$rc"
else
  skip "a failed history append rolls the findings file back" "ln -s copies here"
fi

# --- Case 14: UNREADABLE IS NOT ABSENT ---------------------------------------
#
# Directories stand in for the unreadable file here because the suite may run as
# root, where a chmod 000 file is still readable and the case would pass without
# testing anything.

BDATA="$TEST_TMPDIR/broken-state-data"
BDIR="$BDATA/audit-automation-gaps/$A_KEY"
mkdir -p "$BDIR/history.jsonl" "$BDIR/findings-d8.json"
printf 'd8\n' >"$BDIR/latest"
rc=0
OUT=$(run list --plugin-data "$BDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "list exits 5 when the history file is not a regular file" 5 "$rc"
assert_contains "the report distinguishes unreadable from absent" "$OUT" \
  "that is not the same as having none"
assert_not_contains "list does not report unreadable state as no runs" "$OUT" "no persisted runs"

rc=0
OUT=$(run read --plugin-data "$BDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "read exits 5 when the findings file is not a regular file" 5 "$rc"
assert_contains "read names the findings file it could not read" "$OUT" "findings-d8.json"

LDATA="$TEST_TMPDIR/broken-latest-data"
LDIR="$LDATA/audit-automation-gaps/$A_KEY"
mkdir -p "$LDIR/latest"
rc=0
OUT=$(run read --plugin-data "$LDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "read exits 5 when the latest pointer is not a regular file" 5 "$rc"
assert_contains "the report names the pointer" "$OUT" "the latest pointer exists"

EDATA="$TEST_TMPDIR/empty-latest-data"
EDIR="$EDATA/audit-automation-gaps/$A_KEY"
mkdir -p "$EDIR"
: >"$EDIR/latest"
rc=0
OUT=$(run read --plugin-data "$EDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "an empty latest pointer is damaged state, not absence" 5 "$rc"

FDATA="$TEST_TMPDIR/file-basedir-data"
mkdir -p "$FDATA/audit-automation-gaps/${A_KEY%/*}"
printf 'not a directory\n' >"$FDATA/audit-automation-gaps/$A_KEY"
rc=0
OUT=$(run read --plugin-data "$FDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "read exits 5 when the keyed directory is a regular file" 5 "$rc"
rc=0
OUT=$(run list --plugin-data "$FDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "list exits 5 when the keyed directory is a regular file" 5 "$rc"

# A payload that exists, is readable, is not empty, and still does not parse.
# Publication stages and renames, so this script cannot leave one behind; a
# foreign writer or a stray editor can. Serving those bytes under exit 0 would
# hand the caller something unusable, which is what exit 5 exists to prevent.
CDATA="$TEST_TMPDIR/corrupt-payload-data"
CDIR="$CDATA/audit-automation-gaps/$A_KEY"
mkdir -p "$CDIR"
printf 'corrupt-not-json\n' >"$CDIR/findings-c1.json"
printf 'c1\n' >"$CDIR/latest"
printf '{"run_id":"c1"}\n' >"$CDIR/history.jsonl"
rc=0
OUT=$(run read --plugin-data "$CDATA" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "read exits 5 when the findings payload does not parse" 5 "$rc"
assert_contains "the report says the payload cannot be trusted" "$OUT" "cannot be trusted"
assert_not_contains "the corrupt bytes are never served" "$OUT" "corrupt-not-json"

# --- Case 15: the suffix cap is state exhaustion, not a usage error -----------

CAPDATA="$TEST_TMPDIR/cap-data"
CAPDIR="$CAPDATA/audit-automation-gaps/$A_KEY"
mkdir -p "$CAPDIR"
: >"$CAPDIR/findings-cap.json"
i=2
while [[ "$i" -le 99 ]]; do
  : >"$CAPDIR/findings-cap-$i.json"
  i=$((i + 1))
done
rc=0
OUT=$(run write --plugin-data "$CAPDATA" --root "$REPO_A" --run-id cap --findings "$GOOD" 2>&1) || rc=$?
assert_exit "an exhausted suffix range exits 5, not the usage code" 5 "$rc"
assert_contains "the refusal names the run id whose names are taken" "$OUT" "run id: cap"

# --- Case 16: what the envelope records, and how the pointer is replaced ------
#
# repo_root and written_at are both derived per run. A constant in either place
# is invisible to a round-trip assertion that only checks the field is present,
# so both are compared against a value computed OUTSIDE the script.

ENVELOPE=$(run read --plugin-data "$DATA" --root "$REPO_A" --run-id run-0001)
assert_eq "the envelope records the repo root it was derived from" \
  "$(git -C "$REPO_A" rev-parse --show-toplevel)" \
  "$(printf '%s' "$ENVELOPE" | jq -r '.repo_root')"
B_ENVELOPE=$(run read --plugin-data "$DATA" --root "$REPO_B" --run-id run-0001)
assert_eq "a different repository records a different repo root" \
  "$(git -C "$REPO_B" rev-parse --show-toplevel)" \
  "$(printf '%s' "$B_ENVELOPE" | jq -r '.repo_root')"

stamp_before=$(date -u +%Y-%m-%d)
run write --plugin-data "$DATA" --root "$REPO_A" --run-id stamped --findings "$GOOD" >/dev/null 2>&1
stamp_after=$(date -u +%Y-%m-%d)
stamped=$(run read --plugin-data "$DATA" --root "$REPO_A" --run-id stamped | jq -r '.written_at')
case "$stamped" in
"$stamp_before"T*Z | "$stamp_after"T*Z)
  pass "written_at is stamped when the run is written"
  ;;
*)
  fail "written_at is stamped when the run is written" \
    "expected a UTC stamp dated $stamp_before or $stamp_after, got: $stamped"
  ;;
esac

# The `latest` pointer is a file under a directory anything with write access can
# reach, so the run id it yields is a caller-supplied id by another route.
POISON="$TEST_TMPDIR/poison-data"
PODIR="$POISON/audit-automation-gaps/$A_KEY"
mkdir -p "$PODIR"
run write --plugin-data "$POISON" --root "$REPO_A" --run-id clean --findings "$GOOD" >/dev/null 2>&1
printf '../../etc/passwd\n' >"$PODIR/latest"
rc=0
OUT=$(run read --plugin-data "$POISON" --root "$REPO_A" 2>&1) || rc=$?
assert_exit "a poisoned latest pointer is refused" 2 "$rc"
assert_contains "the refusal names the plain-segment rule" "$OUT" "plain path segment"

# 16a: NEGATIVE. Delete the validation on the pointer path and the poisoned id
# reaches path construction.
BROKEN_PTR="$TEST_TMPDIR/broken-pointer.sh"
# shellcheck disable=SC2016 # sed program text: the $ is a literal character in the script being mutated
sed 's@validate_run_id "$run_id"@:@' "$SCRIPT" >"$BROKEN_PTR"
# shellcheck disable=SC2016 # grep pattern text: same literal $ as the sed above
if grep -qF 'validate_run_id "$run_id"' "$BROKEN_PTR"; then
  fail "negative pointer-validation case could not be constructed" \
    "the sed target no longer matches findings-state.sh, so the pointer validation is UNVERIFIED by this run"
else
  rc=0
  broken_out=$(run_copy "$BROKEN_PTR" read --plugin-data "$POISON" --root "$REPO_A" 2>&1) || rc=$?
  assert_not_contains "with the pointer validation deleted the poisoned id is no longer refused" \
    "$broken_out" "plain path segment"
  assert_contains "and it reaches the filesystem as a traversing path" \
    "$broken_out" "findings-../../etc/passwd.json"
fi

# `latest` is REPLACED, never written through. A `cp` would follow whatever the
# name already is and clobber it, and would let a reader see a half pointer.
PTRDATA="$TEST_TMPDIR/pointer-data"
PTRDIR="$PTRDATA/audit-automation-gaps/$A_KEY"
mkdir -p "$PTRDIR"
if host_makes_symlinks; then
  DECOY="$TEST_TMPDIR/decoy-pointer"
  printf 'decoy\n' >"$DECOY"
  ln -s "$DECOY" "$PTRDIR/latest"
  run write --plugin-data "$PTRDATA" --root "$REPO_A" --run-id ptr --findings "$GOOD" >/dev/null 2>&1
  assert_eq "the write does not follow the old pointer and clobber its target" "decoy" "$(cat "$DECOY")"
  if [[ -L "$PTRDIR/latest" ]]; then
    fail "the latest pointer is replaced, not written through" "it is still a symlink to the decoy"
  else
    pass "the latest pointer is replaced, not written through"
  fi
  assert_eq "the replaced pointer names the run just written" "ptr" "$(cat "$PTRDIR/latest")"
else
  skip "the latest pointer is replaced, not written through" "ln -s copies here"
  run write --plugin-data "$PTRDATA" --root "$REPO_A" --run-id ptr --findings "$GOOD" >/dev/null 2>&1
fi
assert_eq "no staged pointer temporary is left behind" "0" \
  "$(find "$PTRDIR" -name 'latest.*' | wc -l | tr -d ' ')"

# --- Case 17: A MISSING TOOL IS NOT A DAMAGED ARTIFACT ------------------------
#
# `read` parses the stored envelope with `jq` before serving it. On a host with
# no `jq` that command fails with exit 127, which is indistinguishable from a
# document that did not parse unless the prerequisite is checked first. Without
# the check a perfectly valid persisted run is reported under exit 5 as state an
# external writer corrupted, which is the script lying about the operator's
# data: the artifact is fine, the machine is missing a tool. The contract puts a
# missing prerequisite at exit 2, so that is what this asserts.
#
# `jq` is made unavailable by running the script under a PATH holding symlinks
# to the tools it needs and nothing else. Uninstalling `jq` is not an option and
# a wrapper that fails would still satisfy `command -v`.

NOJQ_BIN="$TEST_TMPDIR/nojq-bin"
mkdir -p "$NOJQ_BIN"
for tool in bash sh git date sha256sum shasum tr sed cut head cat mv rm mkdir find wc ln chmod grep; do
  tool_path="$(command -v "$tool" 2>/dev/null)" || continue
  ln -s "$tool_path" "$NOJQ_BIN/$tool" 2>/dev/null || true
done
# Probe the shim rather than trust it: a host where `ln -s` copies, or where a
# needed tool is a shell function or builtin alias, would otherwise turn this
# case into a meaningless failure.
if PATH="$NOJQ_BIN" bash -c 'command -v git >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1' 2>/dev/null; then
  NOJQ_DATA="$TEST_TMPDIR/nojq-data"
  run write --plugin-data "$NOJQ_DATA" --root "$REPO_A" --run-id nojq --findings "$GOOD" >/dev/null 2>&1
  rc=0
  OUT=$(run read --plugin-data "$NOJQ_DATA" --root "$REPO_A" 2>&1) || rc=$?
  assert_exit "the stored run this case reads back is valid while jq is present" 0 "$rc"

  rc=0
  OUT=$(PATH="$NOJQ_BIN" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPT" \
    read --plugin-data "$NOJQ_DATA" --root "$REPO_A" 2>&1) || rc=$?
  assert_exit "read exits 2 with no jq, the prerequisite code and not the damaged-state one" 2 "$rc"
  assert_contains "the refusal names jq as the missing prerequisite" "$OUT" "jq is required"
  assert_not_contains "a valid stored run is never blamed for a missing jq" \
    "$OUT" "cannot be trusted"
  assert_not_contains "and nothing claims an outside writer touched the artifact" \
    "$OUT" "something outside this script wrote it"

  # The gate belongs only where jq is actually used. `list` serves the history
  # file with `cat` and `paths` computes a path, so requiring jq for either
  # would break a host that can still answer both.
  rc=0
  OUT=$(PATH="$NOJQ_BIN" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPT" \
    list --plugin-data "$NOJQ_DATA" --root "$REPO_A" 2>&1) || rc=$?
  assert_exit "list still answers with no jq, because it uses none" 0 "$rc"
  assert_contains "and it serves the recorded run" "$OUT" '"run_id":"nojq"'

  rc=0
  OUT=$(PATH="$NOJQ_BIN" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPT" \
    paths --plugin-data "$NOJQ_DATA" --root "$REPO_A" 2>&1) || rc=$?
  assert_exit "paths still answers with no jq, because it uses none" 0 "$rc"

  # `write` composes the envelope with jq and already gated on it. Asserted here
  # so the three subcommands are judged against one another in one place.
  rc=0
  OUT=$(PATH="$NOJQ_BIN" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPT" \
    write --plugin-data "$NOJQ_DATA" --root "$REPO_A" --run-id nojq-2 --findings "$GOOD" 2>&1) || rc=$?
  assert_exit "write exits 2 with no jq" 2 "$rc"
  assert_contains "write names jq too" "$OUT" "jq is required"
else
  skip "read exits 2 with no jq, the prerequisite code and not the damaged-state one" \
    "a jq-free PATH could not be built here"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed (%d skipped for host capability).\n' "$CASE_NUM" "$SKIPPED"
  exit 0
fi
printf '\n%d/%d checks failed (%d skipped for host capability).\n' "$FAILED" "$CASE_NUM" "$SKIPPED" >&2
exit 1
