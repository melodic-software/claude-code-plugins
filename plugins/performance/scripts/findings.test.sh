#!/usr/bin/env bash
# Tests for findings.py, the go-faster record keeper.
#
# The behaviors under test are refusals and orderings: a finding that breaks
# the accuracy rules is rejected, a measured finding never sorts below a
# candidate, a run cannot start while another holds the lock, and a re-measure
# under different conditions is reported as cannot-quantify rather than as a
# win. Every case drives the CLI and reads its exit code, stdout, or the files
# it wrote under a scratch data folder.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
FINDINGS="$SCRIPT_DIR/findings.py"
readonly FINDINGS

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT

run() { capture "$HARNESS_PYTHON" "$FINDINGS" "$@"; }

AREAS=(session-work how-you-work skills orchestration instructions hooks plugins-startup
  model-cache permissions gates ci-cd pr-review git bash-windows machine tests)

COND='{"repo":"r","machine":"m","harness_version":"2.1.0","model":"opus","workload":"w"}'

# not_checked <area>: one not-checked finding for an area.
not_checked() {
  printf '{"id":"%s-1","key":"%s/none","area":"%s","title":"%s not checked","status":"not-checked","reason_code":"no-data","reason":"no data source; run X to enable"}' \
    "$1" "$1" "$1" "$1"
}

# measured <id> <area> <unit> <value> [extra json fields]
measured() {
  printf '{"id":"%s","key":"%s/%s","area":"%s","title":"t %s","status":"measured","tier":"E1","unit":"%s","value":%s,"command":"cmd","fix_owner":"/performance:goal","horizon":"later","route":"next-run","conditions":%s%s}' \
    "$1" "$2" "$1" "$2" "$1" "$3" "$4" "$COND" "${5:+,$5}"
}

# candidate <id> <area> <source_kind|null> <count>
candidate() {
  local size="null"
  [[ "$3" != null ]] && size="{\"count\":$4,\"source_kind\":\"$3\",\"source\":\"s\"}"
  printf '{"id":"%s","key":"%s/%s","area":"%s","title":"t %s","status":"candidate","tier":"E4","unit":"count","value":null,"expected_size":%s,"command":"measure it","fix_owner":"steps-for-you","fix_steps":["do x"],"horizon":"later","route":"next-run"}' \
    "$1" "$2" "$1" "$2" "$1" "$size"
}

# doc <file> <finding-json>...: a findings file whose areas not named by a
# finding are filled with not-checked entries, so it covers all 16.
doc() {
  local file="$1" area body="" f
  shift
  for f in "$@"; do body+="${body:+,}$f"; done
  for area in "${AREAS[@]}"; do
    [[ "$body" == *"\"area\":\"$area\""* ]] || body+="${body:+,}$(not_checked "$area")"
  done
  printf '{"schema":1,"session_id":"s1","session_evidence":true,"findings":[%s]}\n' "$body" >"$file"
}

# --- 1. validate: a file covering all 16 areas passes ---
doc "$WORK/ok.json"
run validate "$WORK/ok.json"
assert_eq "a complete file validates" "0" "$RUN_RC"

# --- 2. validate: a missing area is named ---
printf '{"schema":1,"session_id":"s1","session_evidence":true,"findings":[%s]}\n' "$(not_checked git)" >"$WORK/few.json"
run validate "$WORK/few.json"
assert_eq "a file missing areas fails" "1" "$RUN_RC"
assert_contains "the missing area is named" "area not covered: session-work" "$RUN_OUT"

# --- 3. validate: not-checked needs an R5 reason code and a reason ---
doc "$WORK/nc.json" '{"id":"git-1","key":"git/none","area":"git","title":"t","status":"not-checked","reason_code":"bored","reason":"x"}'
run validate "$WORK/nc.json"
assert_eq "an unknown reason code fails" "1" "$RUN_RC"
assert_contains "the reason code is named" "git-1: reason_code" "$RUN_OUT"
doc "$WORK/nc2.json" '{"id":"git-1","key":"git/none","area":"git","title":"t","status":"not-checked","reason_code":"no-data"}'
run validate "$WORK/nc2.json"
assert_contains "not-checked without a reason fails" "git-1: reason required" "$RUN_OUT"

# --- 4. validate: flag-only needs a reason ---
doc "$WORK/fo.json" '{"id":"permissions-1","key":"permissions/deny","area":"permissions","title":"t","status":"flag-only"}'
run validate "$WORK/fo.json"
assert_contains "flag-only without a reason fails" "permissions-1: reason required" "$RUN_OUT"

# --- 5. validate: a fewer-checks finding needs a guard metric ---
doc "$WORK/fc.json" "$(measured tests-1 tests elapsed-ms 900 '"effect":"fewer-checks"')"
run validate "$WORK/fc.json"
assert_eq "fewer-checks without guard_metric fails" "1" "$RUN_RC"
assert_contains "the guard metric is named" "tests-1: guard_metric required" "$RUN_OUT"
doc "$WORK/fc2.json" "$(measured tests-1 tests elapsed-ms 900 '"effect":"fewer-checks","guard_metric":"escaped defects per week"')"
run validate "$WORK/fc2.json"
assert_eq "fewer-checks with guard_metric passes" "0" "$RUN_RC"

# --- 6. validate: dropping a check routes to the overengineering audit ---
doc "$WORK/dc.json" "$(measured gates-1 gates elapsed-ms 900 '"effect":"drops-check","guard_metric":"g"')"
run validate "$WORK/dc.json"
assert_contains "drops-check must route to overengineering" "gates-1: drops-check findings route to /overengineering:audit" "$RUN_OUT"

# --- 7. validate: steps-for-you needs steps ---
doc "$WORK/sfy.json" "$(measured git-1 git elapsed-ms 10 '"fix_owner":"steps-for-you"' | sed 's#"fix_owner":"/performance:goal",##')"
run validate "$WORK/sfy.json"
assert_contains "steps-for-you without fix_steps fails" "git-1: fix_steps required" "$RUN_OUT"

# --- 8. validate: citations carry url, as_of date and recheck ---
doc "$WORK/cit.json" "$(measured git-1 git elapsed-ms 10 '"citations":[{"url":"https://git-scm.com/docs","as_of":"soon"}]')"
run validate "$WORK/cit.json"
assert_contains "a citation without a dated as_of fails" "git-1: citation as_of" "$RUN_OUT"
assert_contains "a citation without recheck fails" "git-1: citation recheck" "$RUN_OUT"

# --- 9. R1: a `now` finding must be measured at E1/E2 with a guard and a revert condition ---
NOW='"horizon":"now","guard_metric":"tool errors per turn","revert_if":"a tool error after adoption"'
doc "$WORK/now-ok.json" "$(measured session-work-1 session-work elapsed-ms 5000 "$NOW,\"effect\":\"batching\"" | sed 's/"horizon":"later",//')"
run validate "$WORK/now-ok.json"
assert_eq "a measured E1 now finding with its guard passes" "0" "$RUN_RC"

now_case() { # <label> <expected message> <finding-json>
  doc "$WORK/now.json" "$3"
  run validate "$WORK/now.json"
  assert_contains "$1" "$2" "$RUN_OUT"
}
now_case "now on a candidate is rejected" "skills-1: horizon now needs a measured finding" \
  "$(candidate skills-1 skills session-count 3 | sed "s/\"horizon\":\"later\"/$NOW/")"
now_case "now at E3 is rejected" "session-work-1: horizon now needs tier E1 or E2" \
  "$(measured session-work-1 session-work elapsed-ms 5 "$NOW" | sed -e 's/"horizon":"later",//' -e 's/"tier":"E1"/"tier":"E3"/')"
now_case "now without guard_metric is rejected" "session-work-1: horizon now needs guard_metric" \
  "$(measured session-work-1 session-work elapsed-ms 5 '"revert_if":"x"' | sed 's/"horizon":"later"/"horizon":"now"/')"
now_case "now without revert_if is rejected" "session-work-1: horizon now needs revert_if" \
  "$(measured session-work-1 session-work elapsed-ms 5 '"guard_metric":"g"' | sed 's/"horizon":"later"/"horizon":"now"/')"
now_case "now on a MEDIUM catalog row is rejected" "session-work-1: horizon now cannot rest on a MEDIUM row" \
  "$(measured session-work-1 session-work elapsed-ms 5 "$NOW,\"confidence\":\"MEDIUM\"" | sed 's/"horizon":"later",//')"
now_case "now that lowers effort must be flag-only" "session-work-1: lower-effort is flag-only" \
  "$(measured session-work-1 session-work elapsed-ms 5 "$NOW,\"effect\":\"lower-effort\"" | sed 's/"horizon":"later",//')"
now_case "now that lowers verification depth must be flag-only" "session-work-1: lower-verification is flag-only" \
  "$(measured session-work-1 session-work elapsed-ms 5 "$NOW,\"effect\":\"lower-verification\"" | sed 's/"horizon":"later",//')"
now_case "now that conflicts with a loaded instruction must be flag-only" "session-work-1: a change that conflicts with a loaded instruction is flag-only" \
  "$(measured session-work-1 session-work elapsed-ms 5 "$NOW,\"conflicts_instruction\":\"CLAUDE.md:12\"" | sed 's/"horizon":"later",//')"
doc "$WORK/now-flag.json" "$(measured session-work-1 session-work elapsed-ms 5 "$NOW,\"effect\":\"lower-effort\",\"reason\":\"lowers effort\"" | sed -e 's/"horizon":"later",//' -e 's/"status":"measured"/"status":"flag-only"/')"
run validate "$WORK/now-flag.json"
assert_eq "a lower-effort finding offered as flag-only passes" "0" "$RUN_RC"

# --- 10. rank: elapsed first, then per-unit bands, then candidates by count, never mixed ---
doc "$WORK/rank.json" \
  "$(measured a session-work elapsed-ms 100)" "$(measured b git elapsed-ms 900)" \
  "$(measured c permissions wait-ms 500)" "$(measured d model-cache tokens 10000)" \
  "$(measured e how-you-work turns 7)" "$(candidate f skills session-count 3)" \
  "$(candidate g tests repo-count 9)" "$(candidate h orchestration session-count 8)" \
  "$(candidate i ci-cd null 0)" \
  '{"id":"hooks-1","key":"hooks/deny","area":"hooks","title":"t","status":"flag-only","reason":"a guard"}'
run rank "$WORK/rank.json"
assert_eq "rank exits 0" "0" "$RUN_RC"
want=$'elapsed\tb\nelapsed\tc\nelapsed\ta\nunit:turns\te\nunit:tokens\td\ncandidate:session-count\th\ncandidate:session-count\tf\ncandidate:repo-count\tg\ncandidate:unsized\ti\nflag-only\thooks-1'
assert_eq "report order is elapsed, per-unit bands, candidates by count kind, then flag-only" "$want" "$(head -10 <<<"$RUN_OUT")"
assert_eq "not-checked areas come last" $'not-checked\tmachine-1' "$(tail -1 <<<"$RUN_OUT")"

# --- 11. render: the report shape the user reads ---
run render "$WORK/rank.json"
assert_eq "render exits 0" "0" "$RUN_RC"
assert_contains "measured findings cite their command" '`cmd`' "$RUN_OUT"
assert_contains "candidates are never presented as confirmed" "Unmeasured candidates (not confirmed problems)" "$RUN_OUT"
assert_contains "a candidate names the source of its expected size" "8 (session-count: s)" "$RUN_OUT"
assert_contains "not-checked areas name their reason code" "no-data" "$RUN_OUT"
assert_not_contains "token use is a count, never a price" '$' "$RUN_OUT"
assert_not_contains "no adopt-now prompt without now findings" "Adopt now" "$RUN_OUT"
run render "$WORK/now-ok.json"
assert_contains "now findings get the adopt-now prompt" "Adopt now" "$RUN_OUT"
assert_contains "the adopt-now prompt states the guard" "tool errors per turn" "$RUN_OUT"
assert_contains "the adopt-now prompt states the revert condition" "a tool error after adoption" "$RUN_OUT"
sed 's/"session_evidence":true/"session_evidence":false/' "$WORK/ok.json" >"$WORK/fresh.json"
run render "$WORK/fresh.json"
assert_contains "a fresh session says it has no session evidence" "No session evidence yet: setup scan only." "$RUN_OUT"

# --- 12. lock: one sweep per state key; a stale heartbeat is replaced ---
T0=1790000000
lock_at() { # <epoch> <args...>
  local at="$1"
  shift
  capture env GO_FASTER_NOW="$at" "$HARNESS_PYTHON" "$FINDINGS" lock "$@"
}
D1="$WORK/data/repo-a/wt1"
lock_at "$T0" acquire --data "$D1" --session s1
assert_eq "a free lock is acquired" "0" "$RUN_RC"
assert_contains "the lock records the session" '"session_id": "s1"' "$(cat "$D1/run.lock")"
lock_at "$((T0 + 60))" acquire --data "$D1" --session s2
assert_eq "a fresh lock blocks a second run" "1" "$RUN_RC"
assert_contains "the blocked run names the run in flight" "in-flight session=s1" "$RUN_OUT"
lock_at "$((T0 + 60))" acquire --data "$WORK/data/repo-a/wt2" --session s2
assert_eq "another worktree's state key is not blocked" "0" "$RUN_RC"
lock_at "$((T0 + 50 * 60))" heartbeat --data "$D1" --session s1
assert_eq "the holder refreshes its heartbeat" "0" "$RUN_RC"
lock_at "$((T0 + 70 * 60))" acquire --data "$D1" --session s2
assert_eq "a refreshed heartbeat keeps the lock past the original window" "1" "$RUN_RC"
lock_at "$((T0 + 111 * 60))" acquire --data "$D1" --session s2
assert_eq "a heartbeat older than 60 minutes is stale and replaced" "0" "$RUN_RC"
assert_contains "the replacement is reported" "replaced-stale session=s1" "$RUN_OUT"
lock_at "$((T0 + 112 * 60))" release --data "$D1" --session s1
assert_eq "releasing someone else's lock is refused" "1" "$RUN_RC"
assert_contains "the lock survives a foreign release" '"session_id": "s2"' "$(cat "$D1/run.lock")"
lock_at "$((T0 + 112 * 60))" release --data "$D1" --session s2
assert_eq "the holder releases on finish or abort" "0" "$RUN_RC"
assert_eq "release removes the lock file" "absent" "$([[ -e "$D1/run.lock" ]] && echo present || echo absent)"
lock_at "$((T0 + 113 * 60))" status --data "$D1"
assert_eq "status of a released lock" "free" "$RUN_OUT"

# --- 13. adopt: one record per agreed item, with the route taken and whether it was overridden ---
DA="$WORK/data/adopt"
run adopt --data "$DA" --session s1 --findings "$WORK/now-ok.json" --id session-work-1 --route-taken next-run
assert_eq "adopting a now finding exits 0" "0" "$RUN_RC"
rec="$(head -1 "$DA/adopted.jsonl")"
assert_contains "the record carries the session" '"session_id": "s1"' "$rec"
assert_contains "the record carries the stable key" '"key": "session-work/session-work-1"' "$rec"
assert_contains "the record carries the guard" '"guard_metric": "tool errors per turn"' "$rec"
assert_contains "the record carries the revert condition" '"revert_if": "a tool error after adoption"' "$rec"
assert_contains "the suggested route kept is not an override" '"route_overridden": false' "$rec"
run adopt --data "$DA" --session s1 --findings "$WORK/rank.json" --id b --route-taken performance-chain
assert_contains "a different route than suggested is recorded as overridden" '"route_overridden": true' "$(tail -1 "$DA/adopted.jsonl")"
run adopt --data "$DA" --session s1 --findings "$WORK/rank.json" --id hooks-1 --route-taken next-run
assert_eq "a flag-only finding cannot be adopted" "1" "$RUN_RC"
run adopt --data "$DA" --session s1 --findings "$WORK/rank.json" --id nope --route-taken next-run
assert_eq "an unknown id cannot be adopted" "1" "$RUN_RC"
run adopt --data "$DA" --session s9 --findings "$WORK/rank.json" --id a --route-taken next-run

# --- 14. adopted --session: the list a session re-reads after a compaction (R2) ---
run adopted --data "$DA" --session s1
assert_eq "adopted exits 0" "0" "$RUN_RC"
assert_eq "only this session's adoptions are listed" "2" "$(grep -c '"session_id": "s1"' <<<"$RUN_OUT")"
assert_not_contains "another session's adoption is filtered out" '"s9"' "$RUN_OUT"
run adopted --data "$WORK/data/none" --session s1
assert_eq "no adoptions yet is empty, not an error" "0|" "$RUN_RC|$RUN_OUT"

# --- 15. compare: a re-measure counts only under the recorded conditions (AC9) ---
DC="$WORK/data/compare"
doc "$WORK/m1.json" "$(measured git-status git elapsed-ms 900)"
run compare --data "$DC" --findings "$WORK/m1.json" --id git-status
assert_eq "the first measure is stored as the baseline" "baseline-recorded git/git-status" "$RUN_OUT"
doc "$WORK/m2.json" "$(measured git-status git elapsed-ms 600)"
run compare --data "$DC" --findings "$WORK/m2.json" --id git-status
assert_eq "matching conditions compare against the baseline" \
  "compared git/git-status before=900 after=600 unit=elapsed-ms delta=-300" "$RUN_OUT"
sed 's/"model":"opus"/"model":"sonnet"/' "$WORK/m2.json" >"$WORK/m3.json"
run compare --data "$DC" --findings "$WORK/m3.json" --id git-status
assert_eq "a different model is cannot-quantify" "cannot-quantify git/git-status: differs in model" "$RUN_OUT"
sed 's/"unit":"elapsed-ms"/"unit":"wait-ms"/' "$WORK/m2.json" >"$WORK/m4.json"
run compare --data "$DC" --findings "$WORK/m4.json" --id git-status
assert_eq "a different unit is cannot-quantify" "cannot-quantify git/git-status: differs in unit" "$RUN_OUT"
sed 's/"workload":"w"/"workload":""/' "$WORK/m2.json" >"$WORK/m5.json"
run compare --data "$DC" --findings "$WORK/m5.json" --id git-status
assert_eq "an unrecorded condition is cannot-quantify" "cannot-quantify git/git-status: differs in workload" "$RUN_OUT"
run compare --data "$DC" --findings "$WORK/rank.json" --id f
assert_eq "a candidate has nothing to compare" "1" "$RUN_RC"

# --- 16. lint-catalog: every row is a dated pointer record; non-HIGH rows are candidate-only ---
CAT="$WORK/catalog"
mkdir -p "$CAT"
HDR='| class | area | cause | measure | remedy | accuracy_guard | fix_owner | confidence | candidate_only | pointer | as_of | recheck_trigger |
|---|---|---|---|---|---|---|---|---|---|---|---|'
row() { # <class> <confidence> <candidate_only> <pointer> <as_of> <recheck>
  printf '| %s | git | c | m \\| n | r | g | steps-for-you | %s | %s | %s | %s | %s |\n' "$@"
}
printf '%s\n%s\n' "$HDR" "$(row fsmonitor HIGH no https://git-scm.com/docs 2026-09-01 'git 3.0 ships')" >"$CAT/git.md"
run lint-catalog "$CAT"
assert_eq "a well-formed catalog passes" "0" "$RUN_RC"
lint_case() { # <label> <expected message> <row>
  printf '%s\n%s\n' "$HDR" "$3" >"$CAT/bad.md"
  run lint-catalog "$CAT/bad.md"
  assert_eq "$1 exits 1" "1" "$RUN_RC"
  assert_contains "$1" "$2" "$RUN_OUT"
}
lint_case "a row without as_of fails" "bad.md:3: x: as_of must be YYYY-MM-DD" \
  "$(row x HIGH no https://a.example '' t)"
lint_case "a MEDIUM row not marked candidate-only fails" "bad.md:3: x: a MEDIUM row must be candidate_only yes" \
  "$(row x MEDIUM no https://a.example 2026-09-01 t)"
lint_case "an unknown confidence fails" "bad.md:3: x: confidence must be one of" \
  "$(row x SURE no https://a.example 2026-09-01 t)"
lint_case "a row without a pointer fails" "bad.md:3: x: pointer must be a URL" \
  "$(row x HIGH no '' 2026-09-01 t)"
lint_case "a row without a recheck trigger fails" "bad.md:3: x: recheck_trigger required" \
  "$(row x HIGH no https://a.example 2026-09-01 '')"
rm -f "$CAT/bad.md"
printf '# nothing here\n' >"$WORK/empty.md"
run lint-catalog "$WORK/empty.md"
assert_contains "input with no catalog rows fails" "no catalog rows" "$RUN_OUT"

# --- 17. transcript-counts: per-tool calls, errors and wait, repeats, tokens once per message ---
TR="$WORK/session.jsonl"
ts() { printf '2026-10-03T10:00:%02d.000Z' "$1"; }
use() { # <second> <msg-id> <tool-id> <name> <input-json> <output-tokens>
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","content":[{"type":"tool_use","id":"%s","name":"%s","input":%s}],"usage":{"input_tokens":10,"output_tokens":%s}}}\n' \
    "$(ts "$1")" "$2" "$3" "$4" "$5" "$6"
}
result() { # <second> <tool-id> <is_error>
  printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"%s","is_error":%s}]}}\n' "$(ts "$1")" "$2" "$3"
}
{
  printf '{"type":"user","timestamp":"%s","message":{"content":"speed this up"}}\n' "$(ts 0)"
  use 1 m1 t1 Read '{"file_path":"a.py"}' 5
  use 1 m1 t1 Read '{"file_path":"a.py"}' 7 # streaming repeat of m1: counted once
  result 3 t1 false
  use 4 m2 t2 Read '{"file_path":"a.py"}' 5
  result 5 t2 true
  use 6 m3 t3 Bash '{"command":"make test"}' 5
  result 16 t3 false
  use 17 m4 t4 Bash '{"command":"make test"}' 5
  result 27 t4 false
  use 28 m5 t5 Skill '{"skill":"performance:goal"}' 5
  result 29 t5 false
} >"$TR"
run transcript-counts "$TR"
assert_eq "transcript-counts exits 0" "0" "$RUN_RC"
q() { jq -r "$1" <<<"$RUN_OUT"; }
assert_eq "elapsed spans first to last record" "29000" "$(q .elapsed_ms)"
assert_eq "typed turns are counted" "1" "$(q .typed_turns)"
assert_eq "tool calls are counted per tool" "2 2 1" "$(q '"\(.tools.Read.calls) \(.tools.Bash.calls) \(.tools.Skill.calls)"')"
assert_eq "tool wait is use-to-result time per tool" "3000 20000" "$(q '"\(.tools.Read.wait_ms) \(.tools.Bash.wait_ms)"')"
assert_eq "tool errors are counted per tool" "1" "$(q .tools.Read.errors)"
assert_eq "a re-read file is counted" "2" "$(q '.repeated_reads["a.py"]')"
assert_eq "a re-run command is counted" "2" "$(q '.repeated_commands["make test"]')"
assert_eq "skills invoked are counted" "1" "$(q '.skills["performance:goal"]')"
assert_eq "a streamed message's tokens count once, last record wins" "27" "$(q .tokens.output)"
run transcript-counts "$WORK/missing.jsonl"
assert_eq "a missing transcript is an input error" "2" "$RUN_RC"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
