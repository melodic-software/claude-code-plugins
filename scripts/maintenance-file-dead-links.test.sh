#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq programs and markdown code spans are literal
# Runs the two step bodies of .github/workflows/maintenance-file-dead-links.yml
# under the shell Actions gives a step with no `shell:` (bash -e): `Check the
# dead links` against artifact fixtures, and `Rewrite the rollup issue`
# against a stub `gh` that applies the step's own --jq filter to a fixture
# issue list and logs every write. Also checks the workflow's shape: the
# trigger names the link-check workflow, and each job holds one scope.
# test-scope: .github/workflows/maintenance-file-dead-links.yml
# test-scope: .github/workflows/maintenance-check-links-online*.yml
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/maintenance-file-dead-links.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

# The sync-managed link-check caller. The sync adds the stem-matching file and
# never deletes the earlier one, so both can exist; the stem-matching one wins.
CALLER="$ROOT/.github/workflows/maintenance-check-links-online.yml"
if [[ ! -f "$CALLER" ]]; then
  CALLER="$ROOT/.github/workflows/maintenance-check-links-online-claude-code-plugins.yml"
fi
if [[ ! -f "$CALLER" ]]; then
  fail "no link-check caller under .github/workflows/maintenance-check-links-online*.yml"
  test_harness::report
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export TMPDIR="$TMP_ROOT"

# The `run: |` body of the step named $1, de-indented.
step_body() {
  awk -v name="      - name: $1" '$0 == name { on = 1; next }
    on && /^      - / { exit }
    on { print }' "$WORKFLOW" |
    awk '/^        run: \|$/ { on = 1; next }
      on && /^          / { print substr($0, 11); next }
      on && /^[[:blank:]]*$/ { print ""; next }
      on { exit }'
}
step_body 'Check the dead links' >"$TMP_ROOT/read.sh"
step_body 'Rewrite the rollup issue' >"$TMP_ROOT/file.sh"
for body in read file; do
  if [[ ! -s "$TMP_ROOT/$body.sh" ]]; then
    fail "no $body step with a run: | body in $WORKFLOW"
    test_harness::report
    exit 1
  fi
done
# The rollup marker as the workflow sets it.
MARKER="$(sed -n 's/^          MARKER: //p' "$WORKFLOW")"

# --- Workflow shape -----------------------------------------------------------
job() { awk -v j="  $1:" '$0 == j { on = 1; next } on && /^  [a-z-]+:$/ { exit } on' "$WORKFLOW"; }
scopes() { grep -oE '^ +[a-z-]+: (read|write)( |$)' | sed 's/^ *//; s/ *$//' | sort | paste -sd ' '; }
caller_name="$(sed -n 's/^name: //p' "$CALLER")"
triggers="$(awk '/^  workflow_run:/ { on = 1; next } on && /^  [a-z]/ { exit } on' "$WORKFLOW")"
filter="$(sed -n 's/^ *workflows: \[\(.*\)\]$/\1/p' <<<"$triggers")"
if [[ -n "$caller_name" && ", $filter, " == *", $caller_name, "* && "$triggers" == *"types: [completed]"* ]]; then
  ok "workflow_run fires on completed $caller_name runs"
else
  fail "workflow_run does not name the link-check workflow '$caller_name': '$triggers'"
fi
if grep -q '^permissions: {}$' "$WORKFLOW"; then
  ok "the workflow grants nothing by default"
else
  fail "the workflow-level permissions are not {}"
fi
if [[ "$(job read | scopes)" == 'actions: read' ]]; then
  ok "the read job holds actions: read alone"
else
  fail "the read job's permissions are not exactly actions: read: '$(job read | scopes)'"
fi
if [[ "$(job file | scopes)" == 'issues: write' ]] && ! grep -qE 'uses:|actions/checkout' <<<"$(job file)"; then
  ok "the file job holds issues: write alone and checks out nothing"
else
  fail "the file job's permissions are not exactly issues: write, or it uses an action"
fi
if grep -q 'name: link-check-online-dead-links$' <<<"$(job read)"; then
  ok "the read job downloads the ci-workflows link-check-online-dead-links artifact"
else
  fail "the read job does not download link-check-online-dead-links"
fi
if [[ "$MARKER" == '<!-- link-check-dead-pointer rollup -->' ]]; then
  ok "the rollup marker is the fixed link-check-dead-pointer rollup comment"
else
  fail "the rollup marker is '$MARKER'"
fi

# --- Check the dead links -----------------------------------------------------
run_read() { # <download outcome> <conclusion> <fixture or ''> [MAX_LINKS]
  local out="$TMP_ROOT/read-output" fixture="$TMP_ROOT/dead-links.json"
  : >"$out"
  rm -f "$fixture"
  [[ -n "$3" ]] && printf '%s' "$3" >"$fixture"
  READ_LOG="$(env -i PATH="$PATH" DOWNLOAD="$1" RUN_CONCLUSION="$2" DEAD_LINKS="$fixture" \
    MAX_LINKS="${4:-50}" GITHUB_OUTPUT="$out" bash -e "$TMP_ROOT/read.sh" 2>&1)"
  READ_STATUS=$?
  READ_OUT="$(cat "$out")"
  READ_LINKS="$(awk '/^links<</ { on = 1; next } on && /^EOF_/ { exit } on' "$out")"
}

good='{"url":"https://example.com/gone","status":404,"detail":"Not Found","locations":[{"path":"docs/a.md","line":3,"column":1},{"path":"docs/b c.md","line":null}]}'
other='{"url":"https://example.org/x","status":null,"detail":"Network error\nreset","locations":[{"path":"README.md","line":9}]}'
# shellcheck disable=SC2016 # literal backticks in the fixture
tick='{"url":"https://example.com/`x`","status":404,"detail":"","locations":[{"path":"a.md","line":1}]}'
ftp='{"url":"ftp://example.com/f","status":404,"detail":"","locations":[{"path":"a.md","line":1}]}'
badpath='{"url":"https://example.net/p","status":404,"detail":"","locations":[{"path":"a`b.md","line":1}]}'

run_read success failure "[$good,$other,$tick,$ftp,$badpath]"
if ((READ_STATUS == 0)) && [[ "$(jq -r '[.[].url] | join(" ")' <<<"$READ_LINKS")" == 'https://example.com/gone https://example.org/x' ]]; then
  ok "valid links pass; a backtick URL, a non-http URL and a link left with no safe path are dropped"
else
  fail "the read step kept the wrong links: status $READ_STATUS, links '$READ_LINKS', log $READ_LOG"
fi
if [[ "$READ_LOG" == *"::warning::dropped 3 of 5 malformed dead-link entries"* ]]; then
  ok "dropped links are reported as a warning"
else
  fail "no warning for dropped links: $READ_LOG"
fi
if [[ "$(jq -c '.[0]' <<<"$READ_LINKS")" == '{"url":"https://example.com/gone","status":404,"locations":[{"path":"docs/a.md","line":3},{"path":"docs/b c.md","line":null}],"more_locations":0}' ]]; then
  ok "the server's text is dropped and locations keep path and line"
else
  fail "links are not normalized: $READ_LINKS"
fi

run_read success failure "[$good,$other]" 1
if ((READ_STATUS == 0)) && [[ "$(jq 'length' <<<"$READ_LINKS")" == 1 && "$READ_OUT" == *$'\nmore=1\n'* ]]; then
  ok "at most MAX_LINKS links are handed on, with the count over the cap"
else
  fail "MAX_LINKS did not cap the links: $READ_OUT"
fi

run_read success success "[]"
if ((READ_STATUS == 0)) && [[ "$READ_LINKS" == '[]' && "$READ_OUT" == found=true* ]]; then
  ok "an empty list is handed on, so the rollup can close"
else
  fail "an empty list was not handed on: $READ_STATUS $READ_OUT"
fi

run_read success failure "[$tick,$ftp,$badpath]"
if ((READ_STATUS == 0)) && [[ -z "$READ_OUT" && "$READ_LOG" == *"::warning::every dead-link entry failed the shape check"* ]]; then
  ok "an artifact whose every entry is malformed hands on nothing, so the rollup is not closed"
else
  fail "an all-malformed artifact handed on a list: $READ_STATUS $READ_OUT $READ_LOG"
fi

run_read failure success ''
if ((READ_STATUS == 0)) && [[ -z "$READ_OUT" && "$READ_LOG" != *::warning::* ]]; then
  ok "a green run with no artifact (property off) hands on nothing, quietly"
else
  fail "a green run with no artifact did not exit quietly: $READ_STATUS $READ_LOG"
fi

run_read failure failure ''
if ((READ_STATUS == 0)) && [[ -z "$READ_OUT" && "$READ_LOG" == *"::warning::the red link-check run left no dead-links artifact"* ]]; then
  ok "a red run with no artifact warns and hands on nothing"
else
  fail "a red run with no artifact did not warn: $READ_STATUS $READ_LOG"
fi

run_read success failure '{"url":"https://example.com"}'
if ((READ_STATUS == 1)) && [[ "$READ_LOG" == *"::error::the dead-links artifact is not a JSON array"* ]]; then
  ok "an artifact that is not an array fails the job"
else
  fail "a non-array artifact did not fail: $READ_STATUS $READ_LOG"
fi

# --- Rewrite the rollup issue -------------------------------------------------
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Listing: apply the step's --jq filter to the fixture issues. Writes: log
# them, a JSON body read from stdin (--input -) as one compact I line; an
# issue create answers number 9.
if [[ "${GH_LIST_STATUS:-0}" != 0 && " $* " == *" --paginate "* ]]; then
  exit "$GH_LIST_STATUS"
fi
args=("$@") filter='' method=GET path=''
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    --jq) filter="${args[i + 1]}" ;;
    -X) method="${args[i + 1]}" ;;
    repos/*) path="${args[i]}" ;;
  esac
done
if [[ "$method" == GET ]]; then
  jq -r "$filter" "$GH_ISSUES"
  exit
fi
{
  printf '%s %s\n' "$method" "$path"
  for ((i = 0; i < ${#args[@]}; i++)); do
    [[ "${args[i]}" == -f ]] && printf 'F %s\n' "${args[i + 1]%%$'\n'*}"
    [[ "${args[i]}" == --input && "${args[i + 1]}" == - ]] && printf 'I %s\n' "$(jq -c .)"
  done
} >>"$GH_LOG"
[[ "$method" == POST && "$path" == */issues && "$filter" == .number ]] && echo 9
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == -f && "${args[i + 1]}" == body=* ]] && printf '%s\n' "${args[i + 1]#body=}" >>"$GH_BODY"
done
exit "${GH_WRITE_STATUS:-0}"
STUB
chmod +x "$TMP_ROOT/bin/gh"

issues() { jq -n --arg m "$MARKER" "$1" >"$TMP_ROOT/issues.json"; }
run_file() { # <links json> [VAR=value ...]
  local links="$1"
  shift
  : >"$TMP_ROOT/gh.log"
  : >"$TMP_ROOT/body"
  : >"$TMP_ROOT/summary"
  FILE_LOG="$(env -i PATH="$TMP_ROOT/bin:$PATH" GH_ISSUES="$TMP_ROOT/issues.json" GH_LOG="$TMP_ROOT/gh.log" \
    GH_BODY="$TMP_ROOT/body" GITHUB_REPOSITORY=o/r GITHUB_STEP_SUMMARY="$TMP_ROOT/summary" \
    LINKS="$links" MORE=0 RUN_URL=https://github.com/o/r/actions/runs/1 MARKER="$MARKER" \
    DEMOTION_PATH=https://example.com/dispositions "$@" bash -e "$TMP_ROOT/file.sh" 2>&1)"
  FILE_STATUS=$?
  GH_WRITES="$(cat "$TMP_ROOT/gh.log")"
  BODY="$(cat "$TMP_ROOT/body")"
  SUMMARY="$(cat "$TMP_ROOT/summary")"
}
two='[{"url":"https://example.com/a","status":404,"locations":[{"path":"docs/a.md","line":7},{"path":"docs/b.md","line":null}]},{"url":"https://example.com/b","status":null,"locations":[{"path":"README.md","line":2}]}]'

# No rollup yet: a marker on a later line, or on a pull request, is not one.
issues '[{number: 4, state: "open", state_reason: null, body: ("intro\n" + $m)},
  {number: 5, state: "open", state_reason: null, body: $m, pull_request: {url: "x"}}]'
run_file "$two"
if ((FILE_STATUS == 0)) && [[ "$GH_WRITES" == "POST repos/o/r/issues
F type=Task
F title=Dead links found by the online link check
F body=$MARKER
POST repos/o/r/issues/9/issue-field-values
I {\"issue_field_values\":[{\"field_id\":48484079,\"value\":\"needs-triage\"}]}" ]]; then
  ok "with no rollup, one issue is opened with no label and Work status needs-triage; a misplaced marker is no rollup"
else
  fail "no rollup did not open one issue: status $FILE_STATUS, writes:
$GH_WRITES
log: $FILE_LOG"
fi
# shellcheck disable=SC2016 # literal markdown code spans
if [[ "$BODY" == *'- [ ] `https://example.com/a`, status 404: `docs/a.md` line 7, `docs/b.md`'* &&
  "$BODY" == *'- [ ] `https://example.com/b`, status none: `README.md` line 2'* &&
  "$BODY" == *"found these links dead in https://github.com/o/r/actions/runs/1"* &&
  "$BODY" == *"(https://example.com/dispositions)"* &&
  "$BODY" == *"Close this only once the link check no longer reports these URLs"* &&
  "$BODY" != *"more, see the run"* ]]; then
  ok "the body lists each link as a task with its status and locations, the run, the demotion path and when to close"
else
  fail "the rollup body is missing a part: $BODY"
fi

run_file "$two" MORE=7
if [[ "$BODY" == *$'\n- +7 more, see the run.\n'* ]]; then
  ok "links over the cap get a +N more line"
else
  fail "no overflow line: $BODY"
fi

# 50 long URLs with 20 locations each on long paths: the read step keeps 5
# locations a link and stays under the 128 KiB a single environment variable
# holds, and the file step keeps the body under the 65,536-character limit.
big="$(jq -cn '[range(53) as $i | {url: ("https://example.com/" + ("u" * 950) + "/\($i)"), status: 404,
  locations: [range(20) as $j | {path: ("docs/" + ("p" * 185) + "/\($j).md"), line: $j}]}]')"
run_read success failure "$big"
if ((READ_STATUS == 0)) && [[ "$(jq -c '[length, (map(.locations | length) | unique), (map(.more_locations) | unique)]' <<<"$READ_LINKS")" == '[50,[5],[15]]' ]] &&
  [[ "$READ_OUT" == *$'\nmore=3\n'* ]] && ((${#READ_LINKS} < 131072)); then
  ok "the read step keeps 5 locations a link, counts the rest, and hands on under 128 KiB (${#READ_LINKS} bytes)"
else
  fail "the read step did not cap locations or size: status $READ_STATUS, ${#READ_LINKS} bytes, $READ_LOG"
fi
run_file "$READ_LINKS" MORE=3
shown="$(grep -c '^- \[ \] ' <<<"$BODY")"
over="$(sed -n 's/^- +\([0-9]*\) more, see the run\.$/\1/p' <<<"$BODY")"
if ((FILE_STATUS == 0 && ${#BODY} <= 60001 && shown > 0 && shown < 50)) && [[ "$over" == "$((50 - shown + 3))" ]] &&
  [[ "$BODY" == *", +15 more locations"* ]] && ! grep -q '/5\.md' <<<"$BODY"; then
  ok "a body over 60,000 characters moves links into the +N more line; each item shows 5 locations and counts the rest"
else
  fail "the big body was not capped: status $FILE_STATUS, ${#BODY} characters, $shown shown, over '$over'"
fi

# An open rollup wins over an older closed one.
issues '[{number: 9, state: "closed", state_reason: "completed", body: $m},
  {number: 8, state: "open", state_reason: null, body: ("\n" + $m + "\n\nold")}]'
run_file "$two"
if ((FILE_STATUS == 0)) && [[ "$GH_WRITES" == "PATCH repos/o/r/issues/8
F body=$MARKER" && "$SUMMARY" == *"Rewrote the rollup #8 with 2 dead links."* ]]; then
  ok "an open rollup has its list rewritten"
else
  fail "the open rollup was not rewritten: $FILE_STATUS $GH_WRITES $FILE_LOG"
fi

run_file '[]'
if ((FILE_STATUS == 0)) && [[ "$GH_WRITES" == "POST repos/o/r/issues/8/comments
F body=The link check reported no dead links in https://github.com/o/r/actions/runs/1: closing.
PATCH repos/o/r/issues/8
F state=closed
F state_reason=completed" ]]; then
  ok "with no dead links, the open rollup gets a comment and closes as completed"
else
  fail "the empty run did not close the rollup: $FILE_STATUS $GH_WRITES $FILE_LOG"
fi

issues '[{number: 3, state: "closed", state_reason: "completed", body: $m},
  {number: 6, state: "closed", state_reason: "completed", body: $m}]'
run_file '[]'
if ((FILE_STATUS == 0)) && [[ -z "$GH_WRITES" ]]; then
  ok "with no dead links and no open rollup, nothing is written"
else
  fail "the empty run wrote with no open rollup: $GH_WRITES"
fi
run_file "$two"
if ((FILE_STATUS == 0)) && [[ "$GH_WRITES" == "PATCH repos/o/r/issues/6
F state=open
F body=$MARKER" && "$SUMMARY" == *"Reopened the rollup #6"* ]]; then
  ok "a rollup closed as completed, the newest, is reopened with the new list"
else
  fail "the completed rollup was not reopened: $FILE_STATUS $GH_WRITES $FILE_LOG"
fi

issues '[{number: 6, state: "closed", state_reason: "not_planned", body: $m}]'
run_file "$two"
if ((FILE_STATUS == 0)) && [[ -z "$GH_WRITES" && "$SUMMARY" == *"the rollup #6 was closed as not planned: left alone"* ]]; then
  ok "a rollup closed as not planned is left alone, and the summary says so"
else
  fail "the not-planned rollup was touched: $FILE_STATUS $GH_WRITES $SUMMARY"
fi

run_file "$two" GH_LIST_STATUS=1
if ((FILE_STATUS == 1)) && [[ -z "$GH_WRITES" && "$FILE_LOG" == *"::error::could not read the dead-link rollup issues"* ]]; then
  ok "a failed rollup read writes nothing and fails"
else
  fail "a failed rollup read did not stop the filer: $FILE_STATUS $GH_WRITES $FILE_LOG"
fi

issues '[]'
run_file "$two" GH_WRITE_STATUS=1
if ((FILE_STATUS != 0)); then
  ok "a failed write fails the job"
else
  fail "a failed write did not fail the job: $FILE_LOG"
fi

test_harness::report
