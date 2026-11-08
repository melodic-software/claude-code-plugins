#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline: get-statuses against a gh stub. The plain answer's shape is the GraphQL
# Issue.issueFieldValues read of one issue (melodic-software/claude-code-plugins,
# 2026-11-05), with the alias the script names. The trusted answers take the shape of
# babysit_merge_policy.py ISSUE_STATUS_QUERY (issueFieldValues plus the field timeline
# events, actor databaseId and issueField fullDatabaseId); the trust list and model take
# the shapes of .github/standards/trusted-actors/trusted-actors.json and the
# models.issue-status block of docs/conventions/pr-pipeline.yaml. Every case pins its
# binding through WORK_ITEM_TRACKER_BINDING.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-statuses.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" github:o/r#1                       # no --field
assert_usage_error "$S" --field                            # no value
assert_usage_error "$S" --field "Work status" --bogus
assert_usage_error "$S" --field "Work status" local-markdown:x#1

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
mkdir -p "$STUB"
# The stub answers a contents read from GH_STUB_ACTORS or GH_STUB_MODEL (a file path, or
# `404` for a missing file) and a graphql read from GH_STUB_ANSWER.
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
args="$*"
for a in "$@"; do
  [[ "$a" != query=@* ]] || args="${args/"$a"/query=$(<"${a#query=@}")}"
done
printf '%s\n' "$args" >>"$GH_STUB_LOG"
[[ -z "${GH_STUB_ERR:-}" ]] || { printf '%s\n' "$GH_STUB_ERR" >&2; exit 1; }
case "$*" in
*contents/trust/actors.json*) src="$GH_STUB_ACTORS" ;;
*contents/trust/model.yaml*) src="$GH_STUB_MODEL" ;;
*) src="$GH_STUB_ANSWER" ;;
esac
[[ "$src" != 404 ]] || { printf 'gh: Not Found (HTTP 404)\n' >&2; exit 1; }
cat "$src"
EOF
chmod +x "$STUB/gh"

PLAIN_BINDING="$TMP_ROOT/plain.json"
printf '%s\n' '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}' >"$PLAIN_BINDING"
# trust_binding <status_trust JSON>: a binding file with that config.github.status_trust.
trust_binding() {
  local path="$TMP_ROOT/trust-$RANDOM.json"
  jq -n --argjson t "$1" '{schema_version:"1.0",provider:"github",config:{lease_ttl_hours:24,github:{status_trust:$t}}}' >"$path"
  printf '%s\n' "$path"
}
TRUST_BINDING="$(trust_binding '{"trusted_actors":"trust/actors.json","model":"trust/model.yaml","lanes_app":"lanes-app[bot]"}')"

PLAIN_ANSWER="$TMP_ROOT/plain-answer.json"
cat >"$PLAIN_ANSWER" <<'JSON'
{"data":{"repository":{
  "i1":{"issueFieldValues":{"nodes":[{"name":"Medium","field":{"name":"Size"}},{"name":"needs-human","field":{"name":"Work status"}}]}},
  "i2":{"issueFieldValues":{"nodes":[{"name":"Medium","field":{"name":"Size"}}]}},
  "i3":null}}}
JSON

# Ids: 100 a listed human; 200 the lanes App; 300 a bot-setter listed with its login;
# 400 a bot-setter the list holds under another login; 999 an account the list lacks.
ACTORS="$TMP_ROOT/actors.json"
cat >"$ACTORS" <<'JSON'
{
  "version": 1,
  "actors": [
    { "id": 100, "login": "alice", "kind": "human" },
    { "id": 200, "login": "lanes-app[bot]", "kind": "bot" },
    { "id": 300, "login": "melodic-x[bot]", "kind": "bot" },
    { "id": 400, "login": "melodic-y[bot]", "kind": "bot" }
  ]
}
JSON
MODEL="$TMP_ROOT/model.yaml"
cat >"$MODEL" <<'YAML'
models:
  issue-status:
    field-id: 777
    bot-setters:
      - id: 41898282
        login: "github-actions[bot]"
      - id: 300
        login: "melodic-x[bot]"
      - id: 400
        login: "melodic-z[bot]"
    options:
      "1": needs-human
      "2": agent-ready
      "3": ready
      "4": needs-owner-decision
YAML

# ev <type: add|change|remove> <actor id> [<option>] [<field id>]: one field timeline event.
ev() {
  jq -nc --arg t "$1" --argjson a "$2" --arg v "${3:-}" --arg f "${4:-777}" '
    {__typename: ({add: "IssueFieldAddedEvent", change: "IssueFieldChangedEvent", remove: "IssueFieldRemovedEvent"}[$t]),
     actor: {__typename: "User", login: "someone", databaseId: $a}, issueField: {fullDatabaseId: $f}}
    + ({add: {value: $v}, change: {newValue: $v}, remove: {}}[$t])'
}
# issue <value or ""> <event>...: one issue node holding that Work status value and those
# events, oldest first, beside an unrelated Size value.
issue() {
  local value="$1"
  shift
  jq -nc --arg v "$value" --argjson events "$(printf '%s\n' "$@" | jq -sc '.')" '
    {issueFieldValues: {nodes: ([{name: "Medium", field: {fullDatabaseId: "888"}}]
       + (if $v == "" then [] else [{name: $v, field: {fullDatabaseId: "777"}}] end))},
     timelineItems: {nodes: $events}}'
}
# answer <file> <alias=issue JSON>...: a graphql answer file.
answer() {
  local file="$1"
  shift
  printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(length > 0) | capture("^(?<k>[^=]+)=(?<v>.*)$") | {key: .k, value: (.v | fromjson)})
    | {data: {repository: from_entries}}' >"$file"
}

run() {
  : >"$LOG"
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" WORK_ITEM_TRACKER_BINDING="${BINDING:-$PLAIN_BINDING}" \
    GH_STUB_ACTORS="${ACTORS_FILE:-$ACTORS}" GH_STUB_MODEL="${MODEL_FILE:-$MODEL}" \
    GH_STUB_ANSWER="${ANSWER:-$PLAIN_ANSWER}" bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
  ERR="$(<"$TMP_ROOT/err")"
}

# --- the plain read: no config.github.status_trust ---
run --field "Work status" "github:o/r#1" "github:o/r#2" "github:o/r#3"
assert_eq "statuses → exit 0" "0" "$RC"
assert_eq "each item's field value, null when unset or unanswered" \
  '{"github:o/r#1":"needs-human","github:o/r#2":null,"github:o/r#3":null}' "$(jq -c '.statuses' <<<"$OUT")"
assert_eq "one query for one repository" "1" "$(wc -l <"$LOG" | tr -d ' ')"
assert_contains "aliases each issue number" "$(cat "$LOG")" "i3: issue(number: 3)"

run --field "Work status" "github:o/r#1" "github:p/q#1"
assert_eq "one query per repository" "2" "$(wc -l <"$LOG" | tr -d ' ')"

run --field "Work status"
assert_eq "no ids → exit 0" "0" "$RC"
assert_eq "no ids → no statuses, no call" '{}|0' "$(jq -c '.statuses' <<<"$OUT")|$(wc -l <"$LOG" | tr -d ' ')"

GH_STUB_ERR="HTTP 403: Forbidden" run --field "Work status" "github:o/r#1"
assert_eq "failed read → mapped auth exit" "4" "$RC"
assert_contains "failed read → gh error reaches stderr" "$ERR" "HTTP 403"

CLAUDE_CODE_REMOTE=true run --field "Work status" "github:o/r#1"
assert_eq "a GraphQL-refusing session → exit 3" "3" "$RC"

# --- the trusted read: the newest counted Work status event decides ---
TRUSTED="$TMP_ROOT/trusted.json"
answer "$TRUSTED" \
  "i1=$(issue ready "$(ev add 100 needs-human)" "$(ev change 999 ready)")" \
  "i2=$(issue agent-ready "$(ev add 100 needs-human)" "$(ev change 41898282 agent-ready)")" \
  "i3=$(issue ready "$(ev add 100 needs-human)" "$(ev change 300 ready)")" \
  "i4=$(issue ready "$(ev add 100 needs-owner-decision)" "$(ev change 400 ready)")" \
  "i5=$(issue agent-ready "$(ev add 100 needs-human)" "$(ev change 200 agent-ready)")" \
  "i6=$(issue "" "$(ev add 100 needs-human)" "$(ev remove 300)")" \
  "i7=$(issue needs-human "$(ev add 999 needs-human)" "$(ev add 100 ready 888)")" \
  "i8=$(issue "" "$(ev add 100 needs-human)" "$(ev remove 999)")"
ids=()
for n in 1 2 3 4 5 6 7 8; do ids+=("github:o/r#$n"); done
BINDING="$TRUST_BINDING" ANSWER="$TRUSTED" run --field "Work status" "${ids[@]}"
assert_eq "trusted read → exit 0" "0" "$RC"
st() { jq -r --arg id "github:o/r#$1" '.statuses[$id] | tostring' <<<"$OUT"; }
assert_eq "a human's hold stands over an unlisted account's ready" "needs-human" "$(st 1)"
assert_eq "a bot-setter's agent-ready does not count, so the human's hold stands" "needs-human" "$(st 2)"
assert_eq "a bot-setter the list holds with the same id and login counts for ready" "ready" "$(st 3)"
assert_eq "a bot-setter the list holds under another login does not count" "needs-owner-decision" "$(st 4)"
assert_eq "the lanes App's agent-ready counts" "agent-ready" "$(st 5)"
assert_eq "a counted removal reads null" "null" "$(st 6)"
assert_eq "an unlisted account's hold alone reads null; another field's event is not read" "null" "$(st 7)"
assert_eq "an uncounted removal leaves the counted hold standing" "needs-human" "$(st 8)"

assert_contains "the trusted query, passed as a file, reads the field events" "$(cat "$LOG")" "timelineItems(last: 100"
assert_contains "the trusted query defines its fragments" "$(cat "$LOG")" "fragment who on Actor"
assert_contains "the trust list is read from the item repository" "$(cat "$LOG")" "repos/o/r/contents/trust/actors.json"
assert_contains "the model is read from the item repository" "$(cat "$LOG")" "repos/o/r/contents/trust/model.yaml"

BINDING="$TRUST_BINDING" ANSWER="$TRUSTED" run --field "Work status"
assert_eq "trusted, no ids → no call" '{}|0' "$(jq -c '.statuses' <<<"$OUT")|$(wc -l <"$LOG" | tr -d ' ')"

# The model's ready-state names the one state a bot-setter's value never counts for.
READY_MODEL="$TMP_ROOT/ready-model.yaml"
awk '{ print } /^    field-id: 777$/ { print "    ready-state: ready" }' "$MODEL" >"$READY_MODEL"
BINDING="$TRUST_BINDING" ANSWER="$TRUSTED" MODEL_FILE="$READY_MODEL" run --field "Work status" "${ids[@]}"
assert_eq "a configured ready-state → exit 0" "0" "$RC"
assert_eq "under ready-state ready, a bot-setter's agent-ready counts" "agent-ready" "$(st 2)"
assert_eq "under ready-state ready, a bot-setter's ready does not count" "needs-human" "$(st 3)"

# trust_fails <exit> <name> [run args via env]: the read fails with <exit>, one stderr line
# and nothing on stdout.
trust_fails() {
  BINDING="${BINDING:-$TRUST_BINDING}" ANSWER="${ANSWER:-$TRUSTED}" run --field "Work status" "github:o/r#1"
  assert_eq "$2 → exit $1" "$1" "$RC"
  assert_eq "$2 → no stdout, one stderr line" "|1" "$OUT|$(wc -l <<<"$ERR" | tr -d ' ')"
}

ACTORS_FILE=404 trust_fails 3 "a trust list not on the default branch"
MODEL_FILE=404 trust_fails 3 "a model not on the default branch"
bad="$TMP_ROOT/bad-actors-version.json"
jq '.version = 2' "$ACTORS" >"$bad"
ACTORS_FILE="$bad" trust_fails 3 "a trust list whose version is not 1"
bad="$TMP_ROOT/bad-actors-id.json"
jq '.actors[0].id = 0' "$ACTORS" >"$bad"
ACTORS_FILE="$bad" trust_fails 3 "a trust list holding a non-positive id"
bad="$TMP_ROOT/bad-actors-json.json"
printf '{"version": 1, "actors": [\n' >"$bad"
ACTORS_FILE="$bad" trust_fails 3 "a trust list that is not JSON"
bad="$TMP_ROOT/bad-model-field.yaml"
sed 's/field-id: 777/field-id: abc/' "$MODEL" >"$bad"
MODEL_FILE="$bad" trust_fails 3 "a model whose field-id is not an id"
bad="$TMP_ROOT/bad-model-setter.yaml"
sed '/login: "melodic-x\[bot\]"/d' "$MODEL" >"$bad"
MODEL_FILE="$bad" trust_fails 3 "a bot-setter without a login"
bad="$TMP_ROOT/bad-model-options.yaml"
sed '/"[0-9]": /d' "$MODEL" >"$bad"
MODEL_FILE="$bad" trust_fails 3 "a model that maps no option"
bad="$TMP_ROOT/bad-model-none.yaml"
printf 'models:\n  other: 1\n' >"$bad"
MODEL_FILE="$bad" trust_fails 3 "a model with no models.issue-status block"
bad="$TMP_ROOT/bad-model-ready.yaml"
awk '{ print } /^    field-id: 777$/ { print "    ready-state: agent_ready" }' "$MODEL" >"$bad"
MODEL_FILE="$bad" trust_fails 3 "a ready-state no option maps"
BINDING="$(trust_binding '{"trusted_actors":"trust/actors.json","model":"trust/model.yaml"}')" \
  trust_fails 3 "a status_trust without lanes_app"
BINDING="$(trust_binding '{"trusted_actors":"/etc/actors.json","model":"trust/model.yaml","lanes_app":"a[bot]"}')" \
  trust_fails 3 "a status_trust path that is not repo-relative"
BINDING="$(trust_binding '"trust/actors.json"')" trust_fails 3 "a status_trust that is not a mapping"

full="$TMP_ROOT/full-page.json"
values="$(jq -nc '[range(25) | {name: "x", field: {fullDatabaseId: "\(1000 + .)"}}]')"
answer "$full" "i1=$(issue "" | jq -c --argjson v "$values" '.issueFieldValues.nodes = $v')"
ANSWER="$full" trust_fails 1 "25 field values fill the page"

# window <n>: an answer whose issue holds needs-human and <n> events, none counted.
window() {
  local file="$TMP_ROOT/window-$1.json" events
  events="$(jq -nc --argjson n "$1" '[range($n) | {__typename: "IssueFieldAddedEvent", value: "needs-human",
    actor: {__typename: "User", login: "someone", databaseId: 999}, issueField: {fullDatabaseId: "777"}}]')"
  answer "$file" "i1=$(issue needs-human | jq -c --argjson e "$events" '.timelineItems.nodes = $e')"
  printf '%s\n' "$file"
}
ANSWER="$(window 100)" trust_fails 1 "a full event window with a value and no counted event"
BINDING="$TRUST_BINDING" ANSWER="$(window 99)" run --field "Work status" "github:o/r#1"
assert_eq "below the window, a value with no counted event reads null" "0|null" "$RC|$(st 1)"

unmapped="$TMP_ROOT/unmapped.json"
answer "$unmapped" "i1=$(issue confirmed "$(ev add 100 confirmed)")"
ANSWER="$unmapped" trust_fails 1 "a counted state the model does not map"

# --- status_trust governs Work status alone: another field reads plain ---
PRIORITY="$TMP_ROOT/priority.json"
answer "$PRIORITY" \
  'i1={"issueFieldValues":{"nodes":[{"name":"high","field":{"name":"Priority"}},{"name":"ready","field":{"name":"Work status"}}]}}' \
  'i2={"issueFieldValues":{"nodes":[{"name":"ready","field":{"name":"Work status"}}]}}'
BINDING="$TRUST_BINDING" ANSWER="$PRIORITY" run --field Priority "github:o/r#1" "github:o/r#2"
assert_eq "a trust binding reads another field plainly → exit 0" "0" "$RC"
assert_eq "the named field's value, null when unset" '{"github:o/r#1":"high","github:o/r#2":null}' "$(jq -c '.statuses' <<<"$OUT")"
assert_eq "a Priority read asks for no event history" "0" "$(grep -c timelineItems "$LOG")"

[[ $FAILED -eq 0 ]] || exit 1
