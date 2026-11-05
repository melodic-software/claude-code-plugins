#!/usr/bin/env bash
# Runs the two step bodies of .github/workflows/maintenance-file-dead-links.yml
# under the shell Actions gives a step with no `shell:` (bash -e): `Check the
# dead links` against artifact fixtures, and `File or update one issue per
# dead link` against a stub `gh` that applies the step's own --jq filter to a
# fixture issue list and logs every write. Also checks the workflow's shape:
# the trigger names the link-check workflow, and each job holds one scope.
# test-scope: .github/workflows/maintenance-file-dead-links.yml
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/maintenance-file-dead-links.yml"
CALLER="$ROOT/.github/workflows/maintenance-check-links-online-claude-code-plugins.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

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
step_body 'File or update one issue per dead link' >"$TMP_ROOT/file.sh"
for body in read file; do
  if [[ ! -s "$TMP_ROOT/$body.sh" ]]; then
    fail "no $body step with a run: | body in $WORKFLOW"
    test_harness::report
    exit 1
  fi
done

# --- Workflow shape -----------------------------------------------------------
job() { awk -v j="  $1:" '$0 == j { on = 1; next } on && /^  [a-z-]+:$/ { exit } on' "$WORKFLOW"; }
scopes() { grep -oE '^ +[a-z-]+: (read|write)( |$)' | sed 's/^ *//; s/ *$//' | sort | paste -sd ' '; }
caller_name="$(sed -n 's/^name: //p' "$CALLER")"
triggers="$(awk '/^  workflow_run:/ { on = 1; next } on && /^  [a-z]/ { exit } on' "$WORKFLOW")"
if [[ -n "$caller_name" && "$triggers" == *"workflows: [$caller_name]"* && "$triggers" == *"types: [completed]"* ]]; then
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
if [[ "$(job file | scopes)" == 'issues: write' ]] && ! job file | grep -qE 'uses:|actions/checkout'; then
  ok "the file job holds issues: write alone and checks out nothing"
else
  fail "the file job's permissions are not exactly issues: write, or it uses an action"
fi
if job read | grep -q 'name: link-check-online-dead-links$'; then
  ok "the read job downloads the ci-workflows link-check-online-dead-links artifact"
else
  fail "the read job does not download link-check-online-dead-links"
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
if [[ "$READ_LOG" == *"::warning::kept 2 of 5 dead links"* ]]; then
  ok "dropped links are reported as a warning"
else
  fail "no warning for dropped links: $READ_LOG"
fi
if [[ "$(jq -r '.[1].detail' <<<"$READ_LINKS")" == 'Network error reset' && "$(jq -c '.[0].locations' <<<"$READ_LINKS")" == '[{"path":"docs/a.md","line":3},{"path":"docs/b c.md","line":null}]' ]]; then
  ok "details lose their line breaks and locations keep path and line"
else
  fail "details or locations are not normalized: $READ_LINKS"
fi

run_read success failure "[$good,$other]" 1
if ((READ_STATUS == 0)) && [[ "$(jq 'length' <<<"$READ_LINKS")" == 1 ]]; then
  ok "at most MAX_LINKS links are handed on"
else
  fail "MAX_LINKS did not cap the links: $READ_LINKS"
fi

run_read success success "[]"
if ((READ_STATUS == 0)) && [[ -z "$READ_LINKS" && "$READ_LOG" == *"no dead links to file"* ]]; then
  ok "an empty list hands on nothing"
else
  fail "an empty list handed on links or failed: $READ_STATUS $READ_LOG"
fi

run_read failure success ''
if ((READ_STATUS == 0)) && [[ -z "$READ_LINKS" && "$READ_LOG" != *::warning::* ]]; then
  ok "a green run with no artifact (property off) files nothing, quietly"
else
  fail "a green run with no artifact did not exit quietly: $READ_STATUS $READ_LOG"
fi

run_read failure failure ''
if ((READ_STATUS == 0)) && [[ "$READ_LOG" == *"::warning::the red link-check run left no dead-links artifact"* ]]; then
  ok "a red run with no artifact warns and files nothing"
else
  fail "a red run with no artifact did not warn: $READ_STATUS $READ_LOG"
fi

run_read success failure '{"url":"https://example.com"}'
if ((READ_STATUS == 1)) && [[ "$READ_LOG" == *"::error::the dead-links artifact is not a JSON array"* ]]; then
  ok "an artifact that is not an array fails the job"
else
  fail "a non-array artifact did not fail: $READ_STATUS $READ_LOG"
fi

# --- File or update one issue per dead link -----------------------------------
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Listing: apply the step's --jq filter to the fixture issues. Writes: log them.
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
  done
} >>"$GH_LOG"
if [[ -n "${GH_WRITE_BODIES:-}" ]]; then
  for ((i = 0; i < ${#args[@]}; i++)); do
    [[ "${args[i]}" == -f && "${args[i + 1]}" == body=* ]] && printf '%s\n----\n' "${args[i + 1]#body=}" >>"$GH_WRITE_BODIES"
  done
fi
exit "${GH_WRITE_STATUS:-0}"
STUB
chmod +x "$TMP_ROOT/bin/gh"

sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
link() { jq -cn --arg u "$1" '{url: $u, status: 404, detail: "Not Found", locations: [{path: "docs/a.md", line: 7}]}'; }
url_open='https://example.com/open' url_done='https://example.com/done' url_wont='https://example.com/wont'
url_new1='https://example.com/new1' url_new2='https://example.com/new2'
marker() { printf '<!-- link-check-dead-pointer url-sha256=%s -->' "$(sha "$1")"; }
jq -n --arg mo "$(marker "$url_open")" --arg md "$(marker "$url_done")" --arg mw "$(marker "$url_wont")" \
  --arg mn "$(marker "$url_new1")" --arg mp "$(marker "$url_new2")" '[
  {number: 11, state: "open", state_reason: null, body: ($mo + "\n\nold")},
  {number: 12, state: "closed", state_reason: "completed", body: ($md + "\n")},
  {number: 13, state: "closed", state_reason: "not_planned", body: ($mw + "\n")},
  {number: 14, state: "open", state_reason: null, body: ("intro\n" + $mn), pull_request: null},
  {number: 15, state: "open", state_reason: null, body: $mp, pull_request: {url: "x"}}
]' >"$TMP_ROOT/issues.json"

run_file() { # <links json> [VAR=value ...]
  local links="$1"
  shift
  : >"$TMP_ROOT/gh.log"
  : >"$TMP_ROOT/bodies"
  : >"$TMP_ROOT/summary"
  FILE_LOG="$(env -i PATH="$TMP_ROOT/bin:$PATH" GH_ISSUES="$TMP_ROOT/issues.json" GH_LOG="$TMP_ROOT/gh.log" \
    GH_WRITE_BODIES="$TMP_ROOT/bodies" GITHUB_REPOSITORY=o/r GITHUB_STEP_SUMMARY="$TMP_ROOT/summary" \
    LINKS="$links" RUN_URL=https://github.com/o/r/actions/runs/1 MAX_NEW=1 PACE_SECONDS=0 \
    DEMOTION_PATH=https://example.com/dispositions "$@" bash -e "$TMP_ROOT/file.sh" 2>&1)"
  FILE_STATUS=$?
  GH_WRITES="$(cat "$TMP_ROOT/gh.log")"
}

all="[$(link "$url_open"),$(link "$url_done"),$(link "$url_wont"),$(link "$url_new1"),$(link "$url_new2")]"
run_file "$all"
expected="PATCH repos/o/r/issues/11
F state=open
F body=$(marker "$url_open")
PATCH repos/o/r/issues/12
F state=open
F body=$(marker "$url_done")
POST repos/o/r/issues
F title=Dead link: $url_new1
F body=$(marker "$url_new1")"
if ((FILE_STATUS == 0)) && [[ "$GH_WRITES" == "$expected" ]]; then
  ok "an open record is updated, a completed one reopened, a not-planned one left, and new links filed up to MAX_NEW"
else
  fail "the file step wrote the wrong records: status $FILE_STATUS, writes:
$GH_WRITES
log: $FILE_LOG"
fi
if [[ "$(cat "$TMP_ROOT/summary")" == *"Filed 1, updated 1, reopened 1, left 1 closed as not planned, 0 failed."* &&
  "$(cat "$TMP_ROOT/summary")" == *"- \`$url_new2\`"* ]]; then
  ok "the summary counts each outcome and lists the link over the cap"
else
  fail "the summary is wrong: $(cat "$TMP_ROOT/summary")"
fi
first_body="$(awk '/^----$/ { exit } { print }' "$TMP_ROOT/bodies")"
# shellcheck disable=SC2016 # a literal markdown code span
if [[ "$first_body" == *"- URL: \`$url_open\`"* && "$first_body" == *'- `docs/a.md` line 7'* &&
  "$first_body" == *"- Run: https://github.com/o/r/actions/runs/1"* &&
  "$first_body" == *"(https://example.com/dispositions)"* && "$first_body" == *"- Status: 404 (Not Found)"* ]]; then
  ok "the body names the URL, status, run, each location and the demotion path"
else
  fail "the issue body is missing a part: $first_body"
fi

run_file "[$(link "$url_new1")]" MAX_NEW=5
if [[ "$GH_WRITES" == "POST repos/o/r/issues"* ]]; then
  ok "a marker that is not the first body line, or sits on a pull request, is not a record"
else
  fail "a misplaced marker counted as a record: $GH_WRITES"
fi

run_file "$all" GH_LIST_STATUS=1
if ((FILE_STATUS == 1)) && [[ -z "$GH_WRITES" && "$FILE_LOG" == *"::error::could not read the dead-link records"* ]]; then
  ok "a failed record read files nothing and fails"
else
  fail "a failed record read did not stop the filer: $FILE_STATUS $GH_WRITES $FILE_LOG"
fi

run_file "[$(link "$url_new1")]" GH_WRITE_STATUS=1
if ((FILE_STATUS == 1)) && [[ "$FILE_LOG" == *"::error::could not file the dead-link issue for $url_new1"* ]]; then
  ok "a failed write fails the job"
else
  fail "a failed write did not fail the job: $FILE_STATUS $FILE_LOG"
fi

test_harness::report
