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

# --- 8b. validate: a candidate's expected size is a count with a known source kind (Q26) ---
size_case() { # <label> <expected message> <expected_size json>
  doc "$WORK/size.json" "$(candidate skills-1 skills session-count 3 | sed "s/\"expected_size\":{[^}]*}/\"expected_size\":$3/")"
  run validate "$WORK/size.json"
  assert_contains "$1" "$2" "$RUN_OUT"
}
size_case "an expected size without source_kind fails" "skills-1: expected_size source_kind" '{"count":3,"source":"s"}'
size_case "a vendor percentage is not a source kind" "skills-1: expected_size source_kind" '{"count":3,"source_kind":"vendor-percent","source":"s"}'
size_case "a non-numeric count fails" "skills-1: expected_size count" '{"count":"3","source_kind":"cited","source":"s"}'
size_case "an expected size without its source fails" "skills-1: expected_size source" '{"count":3,"source_kind":"cited"}'

# --- 8c. validate: confidence is one of the catalog labels ---
doc "$WORK/conf.json" "$(measured git-1 git elapsed-ms 10 '"confidence":"measured"')"
run validate "$WORK/conf.json"
assert_contains "an unknown confidence label fails" "git-1: confidence must be one of" "$RUN_OUT"

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
now_case "now that drops a check is rejected" "gates-1: drops-check cannot be horizon now" \
  "$(measured gates-1 gates elapsed-ms 5 "$NOW,\"effect\":\"drops-check\",\"fix_owner\":\"/overengineering:audit\"" | sed -e 's/"horizon":"later",//' -e 's#"fix_owner":"/performance:goal",##')"
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
assert_eq "the holder releases its lock" "0" "$RUN_RC"
assert_eq "release removes the lock file" "absent" "$([[ -e "$D1/run.lock" ]] && echo present || echo absent)"
lock_at "$((T0 + 113 * 60))" status --data "$D1"
assert_eq "status of a released lock" "free" "$RUN_OUT"
: >"$D1/run.lock"
lock_at "$((T0 + 114 * 60))" status --data "$D1"
assert_eq "an unreadable lock reports stale" "stale session=unknown" "$RUN_OUT"
lock_at "$((T0 + 114 * 60))" acquire --data "$D1" --session s3
assert_eq "an unreadable lock is replaced, not held forever" "0" "$RUN_RC"
printf '{"session_id":"s9","heartbeat":"soon"}' >"$D1/run.lock"
lock_at "$((T0 + 115 * 60))" acquire --data "$D1" --session s3
assert_eq "a lock with an unreadable heartbeat is replaced" "0" "$RUN_RC"

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
assert_contains "the record carries the route taken" '"route_taken": "next-run"' "$rec"
assert_contains "the record carries when it was adopted" '"adopted_at": "20' "$rec"
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
assert_eq "a different model is cannot-quantify" "cannot-quantify git/git-status: differs in model; baseline reset" "$RUN_OUT"
sed 's/"unit":"elapsed-ms"/"unit":"wait-ms"/' "$WORK/m2.json" >"$WORK/m4.json"
run compare --data "$DC" --findings "$WORK/m4.json" --id git-status
assert_eq "a different unit is cannot-quantify" "cannot-quantify git/git-status: differs in unit, model; baseline reset" "$RUN_OUT"
sed 's/"workload":"w"/"workload":""/' "$WORK/m2.json" >"$WORK/m5.json"
run compare --data "$DC" --findings "$WORK/m5.json" --id git-status
assert_eq "an unrecorded condition is cannot-quantify" "cannot-quantify git/git-status: differs in unit, workload; baseline kept" "$RUN_OUT"
run compare --data "$DC" --findings "$WORK/m3.json" --id git-status
assert_contains "a changed condition is cannot-quantify" "cannot-quantify git/git-status" "$RUN_OUT"
run compare --data "$DC" --findings "$WORK/m3.json" --id git-status
assert_eq "after a conditions change the new conditions become the baseline" \
  "compared git/git-status before=600 after=600 unit=elapsed-ms delta=0" "$RUN_OUT"
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
use 30 m6 t6 Skill '{"skill":"performance:go-faster"}' 5 >>"$TR"
run transcript-counts "$TR"
assert_eq "work before a model-invoked go-faster is counted" "5" "$(q .work_before_invocation)"
{
  printf '{"type":"user","timestamp":"%s","message":{"content":"how can we go faster?"}}\n' "$(ts 0)"
  use 1 m1 t1 Skill '{"skill":"performance:go-faster"}' 5
} >"$WORK/fresh-model.jsonl"
run transcript-counts "$WORK/fresh-model.jsonl"
assert_eq "a fresh session whose first prompt triggered go-faster has no prior work" "0" "$(q .work_before_invocation)"
printf '{"type":"user","timestamp":"%s","message":{"content":"<command-name>/performance:go-faster</command-name>"}}\n' "$(ts 0)" >"$WORK/fresh-slash.jsonl"
use 1 m1 t1 Bash '{"command":"echo PY"}' 5 >>"$WORK/fresh-slash.jsonl"
run transcript-counts "$WORK/fresh-slash.jsonl"
assert_eq "the skill's own calls after a slash invocation are not prior work" "0" "$(q .work_before_invocation)"
run transcript-counts "$WORK/missing.jsonl"
assert_eq "a missing transcript is an input error" "2" "$RUN_RC"

# --- 18. run-start / add / finish: the sweeper builds its findings file without a Write tool (R4) ---
DR="$WORK/data/runs-test"
capture env GO_FASTER_NOW="$T0" "$HARNESS_PYTHON" "$FINDINGS" run-start --data "$DR" --session s1 --mode unattended --session-evidence false
assert_eq "run-start exits 0" "0" "$RUN_RC"
RUN_DIR="$RUN_OUT"
# The interpreter prints the native spelling of the path, so compare the part it owns.
assert_contains "run-start prints a per-run directory under runs/" "runs-test/runs/$(date -u -d "@$T0" +%Y%m%dT%H%M%SZ)" "$RUN_DIR"
assert_contains "the run header records the mode" '"mode": "unattended"' "$(cat "$RUN_DIR/findings.json")"
capture "$HARNESS_PYTHON" "$FINDINGS" add --run "$RUN_DIR" <<<"$(measured git-1 git elapsed-ms 120)"
assert_eq "a valid finding is added" "0" "$RUN_RC"
capture "$HARNESS_PYTHON" "$FINDINGS" add --run "$RUN_DIR" <<<'{"id":"hooks-1","key":"hooks/x","area":"hooks","title":"t","status":"not-checked"}'
assert_eq "an invalid finding is refused" "1" "$RUN_RC"
assert_contains "the refusal names the rule" "hooks-1: reason required" "$RUN_OUT"
assert_not_contains "a refused finding is not written" "hooks-1" "$(cat "$RUN_DIR/findings.json")"
capture "$HARNESS_PYTHON" "$FINDINGS" add --run "$RUN_DIR" <<<"$(measured git-1 git elapsed-ms 99)"
assert_contains "a duplicate id is refused" "git-1: duplicate id" "$RUN_OUT"
run finish --run "$RUN_DIR"
assert_eq "finish refuses a run that leaves areas uncovered" "1" "$RUN_RC"
assert_contains "finish names the uncovered area" "area not covered: hooks" "$RUN_OUT"
for area in "${AREAS[@]}"; do
  [[ "$area" == git ]] || "$HARNESS_PYTHON" "$FINDINGS" add --run "$RUN_DIR" <<<"$(not_checked "$area")" >/dev/null
done
run finish --run "$RUN_DIR"
assert_eq "finish succeeds once every area is covered" "0" "$RUN_RC"
assert_eq "finish prints the report path" "$RUN_DIR/report.md" "$RUN_OUT"
assert_contains "the report reflects the header" "No session evidence yet: setup scan only." "$(cat "$RUN_DIR/report.md")"

# --- 19. status-timing: git status under trace2, the trace kept in the data folder (R6) ---
REPO="$WORK/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
DT="$WORK/data/timing"
capture bash -c "cd '$REPO' && '$HARNESS_PYTHON' '$FINDINGS' status-timing --data '$DT' --runs 3"
assert_eq "status-timing exits 0 in a repository" "0" "$RUN_RC"
assert_eq "one sample per run" "3" "$(jq '.samples_ms | length' <<<"$RUN_OUT")"
assert_eq "every sample is a positive duration" "true" "$(jq '[.samples_ms[] | . > 0] | all' <<<"$RUN_OUT")"
assert_eq "the label says no index refresh" "status without index refresh" "$(jq -r .label <<<"$RUN_OUT")"
assert_eq "the git version is recorded" "yes" "$([[ "$(jq -r .git_version <<<"$RUN_OUT")" =~ ^[0-9]+\.[0-9]+ ]] && echo yes || echo no)"
capture bash -c "cd '$REPO' && GIT_TRACE2_PERF_BRIEF=1 '$HARNESS_PYTHON' '$FINDINGS' status-timing --data '$DT' --runs 2"
assert_eq "a caller's brief trace format does not empty the samples" "2" "$(jq '.samples_ms | length' <<<"$RUN_OUT")"
assert_eq "the trace is kept in the data folder" "yes" "$([[ -s "$DT/trace2-status.txt" ]] && echo yes || echo no)"
capture bash -c "cd '$WORK' && '$HARNESS_PYTHON' '$FINDINGS' status-timing --data '$DT' --runs 1"
assert_eq "outside a repository it is an input error" "2" "$RUN_RC"

# --- 20. a permission rule that asks or denies is a guard: shown flag-only, never adoptable ---
PERM='{"id":"permissions-1","key":"permissions/ask-rules","area":"permissions","title":"3 ask rules prompt before Bash","status":"flag-only","horizon":"now","reason":"a permission rule that asks or denies is a safety guard; loosening it is yours to decide"}'
doc "$WORK/perm.json" "$PERM"
run validate "$WORK/perm.json"
assert_eq "a flag-only permission-rule finding validates" "0" "$RUN_RC"
run render "$WORK/perm.json"
assert_contains "it is listed under the guards heading" $'## Flagged for you only (guards and unclassifiable checks)\n\n- **3 ask rules prompt before Bash** (permissions, `permissions-1`): a permission rule that asks or denies' "$RUN_OUT"
assert_not_contains "a guard is never offered for adoption, even marked now" "Adopt now" "$RUN_OUT"
run adopt --data "$WORK/data/perm" --session s1 --findings "$WORK/perm.json" --id permissions-1 --route-taken next-run
assert_eq "a permission-rule finding cannot be adopted" "1" "$RUN_RC"
assert_contains "the refusal says why" "permissions-1 is flag-only" "$RUN_OUT"
assert_eq "no adoption is recorded" "absent" "$([[ -e "$WORK/data/perm/adopted.jsonl" ]] && echo present || echo absent)"

# --- 21. Machine is not checked without an elevated recording ---
doc "$WORK/machine.json" '{"id":"machine-1","key":"machine/none","area":"machine","title":"machine not checked","status":"not-checked","reason_code":"needs-elevation","reason":"needs an elevated performance recording; flag-only"}'
run validate "$WORK/machine.json"
assert_eq "a not-checked Machine finding with needs-elevation validates" "0" "$RUN_RC"
run render "$WORK/machine.json"
assert_contains "the report names the reason code and the instrument" "- machine: not checked (needs-elevation). needs an elevated performance recording; flag-only" "$RUN_OUT"
doc "$WORK/machine2.json" '{"id":"machine-1","key":"machine/none","area":"machine","title":"t","status":"not-checked","reason_code":"elevated","reason":"x"}'
run validate "$WORK/machine2.json"
assert_contains "a Machine reason code outside the R5 list fails" "machine-1: reason_code must be one of" "$RUN_OUT"

# --- 22. lint-catalog: the area cell is `all` or ", "-separated area slugs ---
area_row() { # <area cell>
  printf '| x | %s | c | m | r | g | steps-for-you | HIGH | no | https://a.example | 2026-09-01 | t |\n' "$1"
}
printf '%s\n%s\n' "$HDR" "$(area_row 'git, gti')" >"$CAT/bad.md"
run lint-catalog "$CAT/bad.md"
assert_eq "a row with an unknown area slug fails" "1" "$RUN_RC"
assert_contains "the error names the unknown slug" "gti" "$RUN_OUT"
printf '%s\n%s\n' "$HDR" "$(area_row 'ci-cd, gates')" >"$CAT/bad.md"
run lint-catalog "$CAT/bad.md"
assert_eq "a row with two known slugs passes" "0" "$RUN_RC"
printf '%s\n%s\n' "$HDR" "$(area_row all)" >"$CAT/bad.md"
run lint-catalog "$CAT/bad.md"
assert_eq "a row with area all passes" "0" "$RUN_RC"
rm -f "$CAT/bad.md"

# --- 23. ci-timing / pr-timing: gh runs inside findings.py, which prints the numbers (R4) ---
# A fake gh first on PATH answers from fixtures. It refuses unless GH_CONFIG_DIR carries the
# caller's value, so a pass shows the environment was inherited. gh.cmd is the Windows entry
# point, since a Windows interpreter cannot start an extensionless script.
SHIM="$WORK/gh-shim"
FIX="$WORK/gh-fixtures"
GHCWD="$WORK/gh-cwd"
mkdir -p "$SHIM" "$FIX" "$GHCWD"
cat >"$SHIM/gh" <<'GH'
#!/usr/bin/env bash
if [[ "${GH_CONFIG_DIR:-}" != fake-gh-config ]]; then
  printf 'To get started with GitHub CLI, please run:  gh auth login\nAlternatively, populate the GH_TOKEN environment variable.\n' >&2
  exit 4
fi
case "$1 $2" in
  "run list") cat "$FAKE_GH/runs.json" ;;
  "pr list") cat "$FAKE_GH/prs.json" ;;
  api\ repos/*/jobs)
    id="${2%/jobs}"
    id="${id##*/}"
    [[ -f "$FAKE_GH/jobs-$id.json" ]] || { printf 'HTTP 404: Not Found\n' >&2; exit 1; }
    cat "$FAKE_GH/jobs-$id.json"
    ;;
  *) printf 'unexpected gh call: %s\n' "$*" >&2; exit 1 ;;
esac
GH
chmod +x "$SHIM/gh"
printf '@bash "%%~dp0gh" %%*\r\n' >"$SHIM/gh.cmd"

gh_run() { # <findings args...>: run from an empty cwd with the fake gh first on PATH
  RUN_OUT="$(cd "$GHCWD" && env PATH="$SHIM:$PATH" GH_CONFIG_DIR=fake-gh-config FAKE_GH="$FIX" "$HARNESS_PYTHON" "$FINDINGS" "$@" 2>&1)"
  RUN_RC=$?
}

T() { printf '"2026-10-01T%sZ"' "$1"; }
step() { # <name> <conclusion> <start> <end>
  printf '{"name":"%s","conclusion":"%s","started_at":%s,"completed_at":%s}' "$1" "$2" "$(T "$3")" "$(T "$4")"
}
job() { # <name> <conclusion> <created> <started> <completed> <step-json>...
  local name="$1" concl="$2" created="$3" started="$4" completed="$5" IFS=,
  shift 5
  printf '{"name":"%s","conclusion":"%s","created_at":%s,"started_at":%s,"completed_at":%s,"steps":[%s]}' \
    "$name" "$concl" "$(T "$created")" "$(T "$started")" "$(T "$completed")" "$*"
}
listed_run() { # <id> <attempt> <created>
  printf '{"databaseId":%s,"attempt":%s,"createdAt":%s,"startedAt":%s,"updatedAt":%s,"conclusion":"success","workflowName":"CI"}' \
    "$1" "$2" "$(T "$3")" "$(T "$3")" "$(T "$3")"
}
# Six completed runs, newest first as gh lists them; three are re-runs (attempt above 1). Jobs
# exist only for the five newest, so fetching the sixth's would fail the run.
printf '[%s,%s,%s,%s,%s,%s]\n' "$(listed_run 106 1 10:00:00)" "$(listed_run 105 2 09:00:00)" \
  "$(listed_run 104 1 08:00:00)" "$(listed_run 103 3 07:00:00)" "$(listed_run 102 1 06:00:00)" \
  "$(listed_run 101 2 05:00:00)" >"$FIX/runs.json"
# Queue waits of the jobs that ran, in seconds: 10, 30, 20, 60, 40, 50. The skipped deploy job
# would add 130. "Run tests" lasts 90, 150, 100, 80, 200; "Test e2e" 230; the skipped "Publish"
# step 500. Run lengths: 120, 180, 280, 120, 240.
printf '[%s,%s]\n' \
  "$(job build success 10:00:00 10:00:10 10:02:10 "$(step Checkout success 10:00:10 10:00:20)" \
    "$(step 'Run tests' success 10:00:20 10:01:50)" "$(step Lint success 10:01:50 10:02:10)")" \
  "$(job deploy skipped 10:00:00 10:02:10 10:02:10)" >"$FIX/jobs-106.json"
printf '[%s]\n' \
  "$(job build success 09:00:00 09:00:30 09:03:30 "$(step Checkout success 09:00:30 09:00:40)" \
    "$(step 'Run tests' success 09:00:40 09:03:10)" "$(step Lint success 09:03:10 09:03:30)" \
    "$(step Publish skipped 09:03:30 09:11:50)")" >"$FIX/jobs-105.json"
printf '[%s,%s]\n' \
  "$(job build success 08:00:00 08:00:20 08:02:30 "$(step Checkout success 08:00:20 08:00:30)" \
    "$(step 'Run tests' success 08:00:30 08:02:10)" "$(step Lint success 08:02:10 08:02:30)")" \
  "$(job e2e success 08:00:00 08:01:00 08:05:00 "$(step Setup success 08:01:00 08:01:10)" \
    "$(step 'Test e2e' success 08:01:10 08:05:00)")" >"$FIX/jobs-104.json"
printf '[%s]\n' \
  "$(job build success 07:00:00 07:00:40 07:02:40 "$(step Checkout success 07:00:40 07:00:50)" \
    "$(step 'Run tests' success 07:00:50 07:02:10)" "$(step Lint success 07:02:10 07:02:30)")" >"$FIX/jobs-103.json"
printf '[%s]\n' \
  "$(job build success 06:00:00 06:00:50 06:04:50 "$(step Checkout success 06:00:50 06:01:00)" \
    "$(step 'Run tests' success 06:01:00 06:04:20)" "$(step Lint success 06:04:20 06:04:40)")" >"$FIX/jobs-102.json"

gh_run ci-timing --repo o/r
assert_eq "ci-timing exits 0" "0" "$RUN_RC"
q() { jq -r "$1" <<<"$RUN_OUT"; }
assert_eq "queue wait is the even-count median of jobs that ran, skipped job excluded" "35000 wait-ms 6" \
  "$(q '"\(.queue_wait.value) \(.queue_wait.unit) \(.queue_wait.samples)"')"
assert_eq "run length is the median per run in CI minutes" "3 ci-minutes 5" \
  "$(q '"\(.run_length.value) \(.run_length.unit) \(.run_length.samples)"')"
assert_eq "the slowest step by median is named with its job, skipped steps excluded" "e2e|Test e2e|230000|elapsed-ms" \
  "$(q '"\(.slowest_step.job)|\(.slowest_step.step)|\(.slowest_step.value)|\(.slowest_step.unit)"')"
assert_eq "test steps match 'test' in any case; their median over an even count" "125000 elapsed-ms 6" \
  "$(q '"\(.test_steps.value) \(.test_steps.unit) \(.test_steps.samples)"')"
assert_eq "re-runs are runs with attempt above 1, out of the runs listed" "3 count 6" \
  "$(q '"\(.reruns.value) \(.reruns.unit) \(.reruns.samples)"')"
assert_eq "runs listed and runs timed are reported" "6 5" "$(q '"\(.runs_listed) \(.runs_timed)"')"
assert_eq "the run list command is the gh line it ran" \
  "gh run list --repo o/r --limit 20 --status completed --json databaseId,attempt,createdAt,startedAt,updatedAt,conclusion,workflowName" \
  "$(q .reruns.command)"
JOBS_JQ="'[.jobs[] | {name, conclusion, created_at, started_at, completed_at, steps: [(.steps // [])[] | {name, conclusion, started_at, completed_at}]}]'"
assert_eq "one jobs fetch per timed run, newest first" \
  "gh api repos/o/r/actions/runs/106/jobs --jq $JOBS_JQ|gh api repos/o/r/actions/runs/102/jobs --jq $JOBS_JQ|6" \
  "$(q '"\(.commands[1])|\(.commands[5])|\(.commands | length)"')"
assert_eq "a job-based finding cites the jobs lines it ran" "5" "$(q '.queue_wait.command | split("; ") | length')"
assert_eq "nothing is written to the working directory" "" "$(ls -A "$GHCWD")"

# --- 24. pr-timing: review and merge waits from merged pull requests ---
pr() { # <created> <merged> <review-submittedAt...> ; additions and deletions follow as PR_ADD PR_DEL
  local created="$1" merged="$2" reviews="" r
  shift 2
  for r in "$@"; do reviews+="${reviews:+,}{\"state\":\"APPROVED\",\"submittedAt\":\"$r\"}"; done
  printf '{"number":1,"createdAt":"%s","mergedAt":"%s","reviews":[%s],"additions":%s,"deletions":%s,"changedFiles":1}' \
    "$created" "$merged" "$reviews" "$PR_ADD" "$PR_DEL"
}
# First review after open, in hours: 1 (the earlier of two, listed second), 3, 2; one PR has no
# review. Open to merge: 4, 2, 24, 6. Size (additions plus deletions): 15, 100, 50, 2.
{
  printf '['
  PR_ADD=10 PR_DEL=5 pr 2026-09-01T00:00:00Z 2026-09-01T04:00:00Z 2026-09-01T02:00:00Z 2026-09-01T01:00:00Z
  printf ','
  PR_ADD=100 PR_DEL=0 pr 2026-09-02T00:00:00Z 2026-09-02T02:00:00Z
  printf ','
  PR_ADD=30 PR_DEL=20 pr 2026-09-03T00:00:00Z 2026-09-04T00:00:00Z 2026-09-03T03:00:00Z
  printf ','
  PR_ADD=1 PR_DEL=1 pr 2026-09-05T00:00:00Z 2026-09-05T06:00:00Z 2026-09-05T02:00:00Z
  printf ']\n'
} >"$FIX/prs.json"
gh_run pr-timing
assert_eq "pr-timing exits 0" "0" "$RUN_RC"
assert_eq "open to first review is the median of each PR's earliest review" "7200000 wait-ms 3" \
  "$(q '"\(.first_review.value) \(.first_review.unit) \(.first_review.samples)"')"
assert_eq "open to merge is the even-count median" "18000000 wait-ms 4" \
  "$(q '"\(.open_to_merge.value) \(.open_to_merge.unit) \(.open_to_merge.samples)"')"
assert_eq "PR size is the median of additions plus deletions" "32.5 count 4" \
  "$(q '"\(.size.value) \(.size.unit) \(.size.samples)"')"
assert_eq "the pr list command is the gh line it ran" \
  "gh pr list --state merged --limit 20 --json number,createdAt,mergedAt,reviews,additions,deletions,changedFiles" \
  "$(q .first_review.command)"
printf '[]\n' >"$FIX/prs.json"
gh_run pr-timing
assert_eq "no merged PRs is exit 0 with zero samples and no value" "0|0|null" "$RUN_RC|$(q .prs)|$(q .open_to_merge.value)"
assert_eq "nothing is written to the working directory" "" "$(ls -A "$GHCWD")"

# --- 24b. a missing or unparseable timestamp is left out and counted, never a crash ---
# PRs: one with no createdAt (no merge wait, no review wait), one never stamped merged with only
# a pending review; its size still counts. Sizes 15, 4 -> median 9.5.
printf '[%s,%s]\n' \
  '{"number":1,"createdAt":null,"mergedAt":"2026-09-01T04:00:00Z","reviews":[{"submittedAt":"2026-09-01T01:00:00Z"}],"additions":10,"deletions":5,"changedFiles":1}' \
  '{"number":2,"createdAt":"2026-09-02T00:00:00Z","mergedAt":"not a time","reviews":[{"state":"PENDING","submittedAt":null}],"additions":3,"deletions":1,"changedFiles":1}' \
  >"$FIX/prs.json"
gh_run pr-timing
assert_eq "pr-timing survives missing timestamps" "0" "$RUN_RC"
assert_eq "no merge wait from either PR, both counted as excluded" "null 0 2" \
  "$(q '"\(.open_to_merge.value) \(.open_to_merge.samples) \(.open_to_merge.excluded)"')"
assert_eq "no review wait; the PR without createdAt is excluded" "0 1" \
  "$(q '"\(.first_review.samples) \(.first_review.excluded)"')"
assert_eq "size needs no timestamp" "9.5 2 0" "$(q '"\(.size.value) \(.size.samples) \(.size.excluded)"')"
# Jobs: run 102 gains a job that never started and a test step that never completed; every
# median from section 23 stands except run length, which now leaves run 102 out.
printf '[%s,%s]\n' \
  "$(job build success 06:00:00 06:00:50 06:04:50 "$(step Checkout success 06:00:50 06:01:00)" \
    "$(step 'Run tests' success 06:01:00 06:04:20)" "$(step Lint success 06:04:20 06:04:40)")" \
  '{"name":"flaky","conclusion":"failure","created_at":"2026-10-01T06:00:00Z","started_at":null,"completed_at":null,"steps":[{"name":"Unit test","conclusion":"failure","started_at":"2026-10-01T06:00:05Z","completed_at":null}]}' \
  >"$FIX/jobs-102.json"
gh_run ci-timing --repo o/r
assert_eq "ci-timing survives missing timestamps" "0" "$RUN_RC"
assert_eq "the unstarted job is excluded from queue wait and counted" "35000 6 1" \
  "$(q '"\(.queue_wait.value) \(.queue_wait.samples) \(.queue_wait.excluded)"')"
assert_eq "the uncompleted test step is excluded and counted" "125000 6 1" \
  "$(q '"\(.test_steps.value) \(.test_steps.samples) \(.test_steps.excluded)"')"
assert_eq "run 102's unstarted job leaves it out of run length, counted; 120 120 180 280 s remain" "2.5 4 1" "$(q '"\(.run_length.value) \(.run_length.samples) \(.run_length.excluded)"')"

# --- 25. a gh failure exits 1 with one line naming it ---
RUN_OUT="$(cd "$GHCWD" && env -u GH_CONFIG_DIR PATH="$SHIM:$PATH" FAKE_GH="$FIX" "$HARNESS_PYTHON" "$FINDINGS" ci-timing --repo o/r 2>&1)"
RUN_RC=$?
assert_eq "a gh failure exits 1" "1" "$RUN_RC"
assert_eq "the error is one line" "1" "$(wc -l <<<"$RUN_OUT" | tr -d ' ')"
assert_contains "the error names the gh call" "gh run list" "$RUN_OUT"
assert_contains "the error carries gh's first error line" "gh auth login" "$RUN_OUT"
rm -f "$FIX/jobs-104.json"
gh_run ci-timing --repo o/r
assert_eq "a failed jobs fetch exits 1" "1" "$RUN_RC"
assert_contains "the error names the failed fetch and its reason" "runs/104/jobs" "$RUN_OUT"
assert_contains "the error carries the HTTP status" "HTTP 404" "$RUN_OUT"
assert_eq "nothing is written to the working directory" "" "$(ls -A "$GHCWD")"

# --- 26. a sample with one bad timestamp is left out whole and counted, never half-used ---
# Run 201 (12:00): build 12:00:00-12:02:00 and lint started 12:01:00 with an unparseable end, so
# its length is unknown. Run 203 (11:00): build 11:00:00-11:03:00 (3 minutes) and a skipped
# deploy job with no timestamps, which does not make the run unknown.
printf '[%s,%s]\n' "$(listed_run 201 1 12:00:00)" "$(listed_run 203 1 11:00:00)" >"$FIX/runs.json"
printf '[%s,%s]\n' "$(job build success 12:00:00 12:00:00 12:02:00)" \
  '{"name":"lint","conclusion":"success","created_at":"2026-10-01T12:01:00Z","started_at":"2026-10-01T12:01:00Z","completed_at":"garbage","steps":[]}' \
  >"$FIX/jobs-201.json"
printf '[%s,%s]\n' "$(job build success 11:00:00 11:00:00 11:03:00)" \
  '{"name":"deploy","conclusion":"skipped","created_at":"2026-10-01T11:00:00Z","started_at":null,"completed_at":null,"steps":[]}' \
  >"$FIX/jobs-203.json"
gh_run ci-timing --repo o/r
assert_eq "ci-timing exits 0 on a job with an unparseable end" "0" "$RUN_RC"
assert_eq "a run with a non-skipped job missing an end is left out of run length and counted" "3 1 1" \
  "$(q '"\(.run_length.value) \(.run_length.samples) \(.run_length.excluded)"')"
# Run 202 has an unparseable createdAt and no jobs fixture: fetching its jobs would fail the run.
printf '[%s,%s,%s]\n' "$(listed_run 201 1 12:00:00)" \
  '{"databaseId":202,"attempt":2,"createdAt":"garbage","startedAt":null,"updatedAt":null,"conclusion":"success","workflowName":"CI"}' \
  "$(listed_run 203 1 11:00:00)" >"$FIX/runs.json"
gh_run ci-timing --repo o/r
assert_eq "ci-timing exits 0 on a run with an unparseable createdAt" "0" "$RUN_RC"
assert_eq "the undated run is listed, not timed, and counted as excluded" "3 2 1" \
  "$(q '"\(.runs_listed) \(.runs_timed) \(.runs_excluded)"')"
assert_eq "the undated run's jobs are never fetched" "0" "$(q '[.commands[] | select(contains("runs/202/"))] | length')"
assert_eq "re-runs still count every listed run" "1 3" "$(q '"\(.reruns.value) \(.reruns.samples)"')"
# PRs: one with reviews at 1h and an unparseable one (its earliest review is unknown), one with
# only an unparseable review, and one reviewed at 2h. Only the last yields a first-review wait.
printf '[%s,%s,%s]\n' \
  '{"number":1,"createdAt":"2026-09-01T00:00:00Z","mergedAt":"2026-09-01T04:00:00Z","reviews":[{"submittedAt":"2026-09-01T01:00:00Z"},{"submittedAt":"not a time"}],"additions":1,"deletions":0,"changedFiles":1}' \
  '{"number":2,"createdAt":"2026-09-02T00:00:00Z","mergedAt":"2026-09-02T04:00:00Z","reviews":[{"submittedAt":"not a time"}],"additions":1,"deletions":0,"changedFiles":1}' \
  '{"number":3,"createdAt":"2026-09-03T00:00:00Z","mergedAt":"2026-09-03T04:00:00Z","reviews":[{"submittedAt":"2026-09-03T02:00:00Z"}],"additions":1,"deletions":0,"changedFiles":1}' \
  >"$FIX/prs.json"
gh_run pr-timing
assert_eq "pr-timing exits 0 on an unparseable review time" "0" "$RUN_RC"
assert_eq "a PR with an unparseable review time is excluded from first review and counted" "7200000 1 2" \
  "$(q '"\(.first_review.value) \(.first_review.samples) \(.first_review.excluded)"')"
assert_eq "nothing is written to the working directory" "" "$(ls -A "$GHCWD")"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
