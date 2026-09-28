#!/usr/bin/env bash
# Offline tests for the #4306 fail-closed classifier and hook.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/plugins/review/hooks/fail-closed-skill-invocation.py"
CODE_SKILL="$ROOT/plugins/review/skills/code-review/SKILL.md"
SEC_SKILL="$ROOT/plugins/review/skills/security-review/SKILL.md"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

assert_exit() {
  local name="$1" want="$2" got="$3"
  if [[ "$got" -eq "$want" ]]; then
    ok "$name"
  else
    fail "$name expected exit $want, got $got"
  fi
}

run_tool() {
  local payload="$1"
  printf '%s' "$payload" | python3 "$SCRIPT" classify-tool-result >/tmp/fail-closed-out.txt 2>/tmp/fail-closed-err.txt
  return $?
}

run_posted() {
  local lane="$1" body="$2"
  printf '%s' "$body" | LANE_SKILL="$lane" python3 "$SCRIPT" classify-posted >/tmp/fail-closed-out.txt 2>/tmp/fail-closed-err.txt
  return $?
}

run_hook() {
  local payload="$1"
  printf '%s' "$payload" | python3 "$SCRIPT" hook >/tmp/fail-closed-out.txt 2>/tmp/fail-closed-err.txt
  return $?
}

# --- tool results -----------------------------------------------------------
run_tool '{"content":"Execute skill: review:code-review","is_error":true}'
assert_exit "empty code-review tool result fails closed" 3 $?
if [[ "$(cat /tmp/fail-closed-out.txt)" == "degrade" ]]; then
  ok "tool result prints degrade"
else
  fail "tool result stdout"
fi

run_tool '{"content":"Execute skill: review:security-review","is_error":true}'
assert_exit "empty security-review tool result fails closed" 3 $?

run_tool '{"content":"Launching skill: review:code-review"}'
assert_exit "Launching skill is not a failed lane" 0 $?

run_tool '{"content":"Execute skill: review:code-review\n# CI code review\n","is_error":false}'
assert_exit "Execute skill plus a body is loaded" 0 $?

run_tool '{"content":"Execute skill: probe:probe","is_error":true}'
assert_exit "an unrelated skill is outside this lane" 0 $?

run_tool '{"content":[{"type":"text","text":"Execute skill: review:code-review"}],"is_error":true}'
assert_exit "content blocks that are only Execute skill fail closed" 3 $?

run_tool '{"error":"something else broke","is_error":true}'
assert_exit "a different tool error is not this defect" 0 $?

# --- posted text: the #4306 confession, including the wording the old guard missed
# shellcheck disable=SC2016  # backticks are the literal fixture's markdown code spans, not substitution
CONFESSION='**Note on process:** the `review:code-review` skill invocation errored out (returned `Execute skill: review:code-review` with no further content, on two attempts with different `args` shapes). I fell back to performing the review directly against the diff (`git diff origin/main...HEAD`).'

run_posted code-review "$CONFESSION"
assert_exit "issue-comment confession fails the code-review lane" 3 $?

run_posted security-review "$CONFESSION"
assert_exit "the code-review confession does not fail the security lane" 0 $?

run_posted code-review 'No findings. The change matches the tests.'
assert_exit "a clean review stays exit 0" 0 $?

run_posted code-review $'review-lane-fail-closed: code-review\nThe skill body never loaded.'
assert_exit "marker line fails the named lane" 3 $?

# shellcheck disable=SC2016  # backticks are the literal fixture's markdown code span, not substitution
run_posted code-review 'The token `review-lane-fail-closed: code-review` is the reply the skill asks for.'
assert_exit "the marker inside a sentence is not a confession" 0 $?

run_posted code-review 'The fixture mentions Execute skill: review:code-review and nothing more.'
assert_exit "Execute skill without the empty-invocation confession stays exit 0" 0 $?

run_posted code-review 'review:code-review skill invocation errored out. I fell back to a manual fallback.'
assert_exit "errored invocation plus a hand review fails closed" 3 $?

# --- hook -------------------------------------------------------------------
run_hook '{"hook_event_name":"PostToolUseFailure","tool_name":"Skill","error":"Execute skill: review:code-review"}'
assert_exit "PostToolUseFailure hook exits 0" 0 $?
if python3 -c 'import json,sys; d=json.load(open("/tmp/fail-closed-out.txt")); assert d["continue"] is False; assert d["stopReason"].startswith("review-lane-fail-closed: code-review")'; then
  ok "PostToolUseFailure stops the lane"
else
  fail "PostToolUseFailure JSON"
fi

run_hook '{"hook_event_name":"PostToolUseFailure","tool_name":"Skill","error":"Exit code 1\nnot a skill load"}'
assert_exit "other Skill failures do not stop the session" 0 $?
if [[ ! -s /tmp/fail-closed-out.txt ]]; then
  ok "other Skill failures print nothing"
else
  fail "unexpected hook stdout"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' \
  'Invoke /review:code-review now and follow its instructions exactly' \
  '{"content":"Execute skill: review:code-review","is_error":true}' \
  >"$TMP/lane.txt"
run_hook "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","transcript_path":sys.argv[1]}))' "$TMP/lane.txt")"
assert_exit "PreToolUse in the lane exits 0" 0 $?
if python3 -c 'import json; d=json.load(open("/tmp/fail-closed-out.txt")); assert d["continue"] is False'; then
  ok "Bash after an empty skill result stops the lane"
else
  fail "PreToolUse did not stop"
fi

printf '%s\n' \
  'please review this diff' \
  '{"content":"Execute skill: review:code-review","is_error":true}' \
  >"$TMP/seat.txt"
run_hook "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","transcript_path":sys.argv[1]}))' "$TMP/seat.txt")"
if [[ ! -s /tmp/fail-closed-out.txt ]]; then
  ok "a seat session is not stopped by the lane hook"
else
  fail "seat session was stopped"
fi

printf '%s\n' \
  'Invoke /review:code-review now' \
  'Launching skill: review:code-review' \
  >"$TMP/launched.txt"
run_hook "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","transcript_path":sys.argv[1]}))' "$TMP/launched.txt")"
if [[ ! -s /tmp/fail-closed-out.txt ]]; then
  ok "Launching skill does not stop later Bash"
else
  fail "launched skill stopped Bash"
fi

printf '%s\n' \
  'Invoke /review:code-review now' \
  'Launching skill: review:code-review' \
  '{"content":"Execute skill: review:code-review","is_error":true}' \
  >"$TMP/again.txt"
run_hook "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","transcript_path":sys.argv[1]}))' "$TMP/again.txt")"
if python3 -c 'import json; d=json.load(open("/tmp/fail-closed-out.txt")); assert d["continue"] is False'; then
  ok "a later empty result still fails closed"
else
  fail "later empty result was ignored"
fi

printf '%s\n' \
  'Invoke /review:code-review now' \
  'Execute skill: review:code-review' \
  '# CI code review' \
  >"$TMP/body.txt"
run_hook "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","transcript_path":sys.argv[1]}))' "$TMP/body.txt")"
if [[ ! -s /tmp/fail-closed-out.txt ]]; then
  ok "Execute skill followed by a body is not empty"
else
  fail "loaded body was treated as empty"
fi

run_hook '{"hook_event_name":"Stop","last_assistant_message":"review-lane-fail-closed: security-review\nThe skill body never loaded."}'
if python3 -c 'import json; d=json.load(open("/tmp/fail-closed-out.txt")); assert d["stopReason"].startswith("review-lane-fail-closed: security-review")'; then
  ok "Stop blocks a marker reply"
else
  fail "Stop did not block the marker"
fi

run_hook '{"hook_event_name":"Stop","last_assistant_message":"No findings."}'
if [[ ! -s /tmp/fail-closed-out.txt ]]; then
  ok "Stop allows a clean reply"
else
  fail "clean Stop was blocked"
fi

# --- check-lane fixtures ----------------------------------------------------
FAIL_CLOSED_BODIES="$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$CONFESSION")" \
  LANE_SKILL=code-review python3 "$SCRIPT" check-lane >/tmp/fail-closed-out.txt 2>/tmp/fail-closed-err.txt
assert_exit "check-lane fails closed on the confession fixture" 3 $?

FAIL_CLOSED_BODIES='["No findings."]' LANE_SKILL=code-review \
  python3 "$SCRIPT" check-lane >/tmp/fail-closed-out.txt 2>/tmp/fail-closed-err.txt
assert_exit "check-lane stays green when nothing confessed" 0 $?

env -u FAIL_CLOSED_BODIES -u GITHUB_REPOSITORY LANE_SKILL=code-review \
  python3 "$SCRIPT" check-lane >/tmp/fail-closed-out.txt 2>/tmp/fail-closed-err.txt
assert_exit "check-lane fails closed when it cannot read the run" 2 $?

# --- skill contract ---------------------------------------------------------
for skill in "$CODE_SKILL" "$SEC_SKILL"; do
  base="$(basename "$(dirname "$skill")")"
  if grep -q 'reference/headless-skill-grant.md' "$skill"; then
    ok "$base points at the verification record"
  else
    fail "$base lost the verification record pointer"
  fi
  if grep -q "review-lane-fail-closed: $base" "$skill"; then
    ok "$base names its fail-closed marker"
  else
    fail "$base lost its fail-closed marker"
  fi
  if grep -q '^allowed-tools:' "$skill"; then
    ok "$base keeps allowed-tools"
  else
    fail "$base dropped allowed-tools"
  fi
  if grep -q 'Do not review the diff yourself' "$skill"; then
    ok "$base forbids a hand review"
  else
    fail "$base lost the hand-review prohibition"
  fi
  if grep -q -- '--allowedTools "Skill()"' "$skill"; then
    ok "$base names the Skill() workaround"
  else
    fail "$base lost the Skill() workaround"
  fi
done

if python3 - <<'PY' "$CODE_SKILL" "$SEC_SKILL"
import re, sys
failed = False
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    match = re.search(r'^description: "(.*)"$', text, re.M)
    if not match:
        print(f"FAIL: no description in {path}", file=sys.stderr)
        failed = True
        continue
    desc = match.group(1)
    if "resolves in your session" not in desc:
        print(f"FAIL: {path} dropped the presence gate", file=sys.stderr)
        failed = True
    if "Execute skill:" not in desc or "review-lane-fail-closed:" not in desc:
        print(f"FAIL: {path} description does not carry the fail-closed rule", file=sys.stderr)
        failed = True
    if len(desc) > 1536:
        print(f"FAIL: {path} description is {len(desc)} characters", file=sys.stderr)
        failed = True
    else:
        print(f"ok: {path} description is {len(desc)} characters and keeps the gate")
sys.exit(1 if failed else 0)
PY
then
  ok "descriptions stay inside the cap"
else
  fail "description contract"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
