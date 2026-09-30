#!/usr/bin/env bash
# Contract test for test-judge-start.sh, the task-end judge's SessionStart
# hook: it names, once, the verdicts an earlier session never relayed, and
# marks a /clear or fork successor.
# shellcheck disable=SC2016,SC2034  # check() evals its single-quoted condition, which reads these

# shellcheck source=judge-test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/judge-test-helpers.sh"
HOOK="$HOOK_DIR/test-judge-start.sh"
start() { out="$(payload "$1" start "" "{\"hook_event_name\": \"SessionStart\", \"source\": \"$2\"}" | bash "$HOOK" 2>/dev/null)"; }
field() { jq -r "$1 // empty" <<<"$out" 2>/dev/null; }
now="$(date +%s)"
iso() { jq -rn --argjson t "$1" '$t | todate'; }

# ledger <sid> <key-hash> <file> <verdict>: a verdict an earlier session left.
F="$REPO/src/add.test.ts"
js_file "$F" adds
ledger() {
  mkdir -p "$DATA/verdicts/$PKEY/$1"
  jq -cn --arg f "$3" --arg r "$REPO" --arg v "$4" '{file: $f, repo: $r, name: "adds", ordinal: 1, start: 3, end: 5,
    verdict: $v, evidence: ["  expect(add(1, 2)).toBe(3);"], source: "the spec", diff: "", reason: "", model: "opus",
    effort: "medium"}' >"$DATA/verdicts/$PKEY/$1/$2.json"
}

start fresh startup
assert_empty "no ledger: no output" "$out"

# An unrelayed verdict from a session idle over an hour is named once.
record old w1 "$F" null "" null 0 "$(iso $((now - 7200)))"
ledger old k1 "$F" PASS
start new1 startup
assert_contains "an unrelayed verdict from an old session is named" "$(field .systemMessage)" "1 test (0 FLAG, 1 PASS, 0 UNKNOWN)"
f="$(field .systemMessage | sed -n 's/.*Findings: //p')"
check "with the findings file" '[[ -f "$f" && "$(cat "$f")" == *"type: review-findings"* ]]'
start new2 startup
assert_empty "the notice appears once" "$out"

# A relayed verdict is not named.
record old2 w1 "$F" null "" null 0 "$(iso $((now - 7200)))"
ledger old2 k2 "$F" FLAG
mkdir -p "$DATA/relayed/$PKEY/old2"
: >"$DATA/relayed/$PKEY/old2/k2"
start new3 startup
assert_empty "a relayed verdict is not named" "$out"

# One from a session active in the last hour is not named: adoption owns it.
record recent w1 "$F" null "" null 0 "$(iso $((now - 600)))"
ledger recent k3 "$F" PASS
start new4 startup
assert_empty "a verdict from a session active in the last hour is not named" "$out"

# Another repository's (another project key) is not named.
OTHER="$(printf '%s\n%s' "/elsewhere" "$TDIR" | sha256 | cut -c1-16)"
mkdir -p "$DATA/sessions/$OTHER/far" "$DATA/verdicts/$OTHER/far"
cp "$DATA/sessions/$PKEY/old/w1.json" "$DATA/sessions/$OTHER/far/w1.json"
cp "$DATA/verdicts/$PKEY/old/k1.json" "$DATA/verdicts/$OTHER/far/k4.json"
start new5 startup
assert_empty "another repository's verdict is not named" "$out"

# `clear` and `fork` write the successor marker; `startup` and `resume` do not.
for src in clear fork startup resume; do start "succ-$src" "$src"; done
check "clear writes the successor marker" '[[ "$(cat "$DATA/successors/$PKEY/succ-clear")" =~ ^[0-9]+$ ]]'
check "fork writes the successor marker" '[[ -f "$DATA/successors/$PKEY/succ-fork" ]]'
check "startup and resume do not" '[[ ! -e "$DATA/successors/$PKEY/succ-startup" && ! -e "$DATA/successors/$PKEY/succ-resume" ]]'

out="$(payload x start "" '{"source": "clear"}' | CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED='' bash "$HOOK")"
check "test_judge_enabled off: nothing" '[[ -z "$out" && ! -e "$DATA/successors/$PKEY/x" ]]'
check "no real claude was ever called" '[[ ! -e "$TMP/real-claude-called" ]]'
finish
