#!/usr/bin/env bash
# Contract test for credential-sweep.sh against a stub `gh` that serves fixture
# responses keyed by API path, and a stub `gitleaks` unless the case needs the
# real scanner.
#
# Expected values come from the sweep's contract: a hit is reported by rule and
# location and never by value, anything readable but unread is listed under
# GAPS, what the API serves to nobody is listed apart and leaves the exit code
# alone, every request is a GET, the first rate-limit error stops the sweep,
# and the exit code is 0 clean, 1 hits, 2 gaps and no hits, 3 could not start.
#
# The planted token is assembled at run time from two halves, so no line of
# this file matches a gitleaks or GitGuardian token pattern.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/credential-sweep.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PYTHON="$(command -v python3 || command -v python || true)"
prefix='gh''p_'
body='R7kT2vXq9LmN4bWc8YdF3hJs6PzA1uEo5iGt'
PLANTED="$prefix$body"
SINCE=2026-10-01
# The pinned default config's shape, cut to one rule: a global [allowlist]
# whose paths list skips node_modules, the way the upstream default does.
CONFIG_FIXTURE="$(
  cat <<'EOF'
title = "fixture"
minVersion = "v8.25.0"

[allowlist]
description = "global allow lists"
paths = [
    '''(?:^|/)node_modules(?:/.*)?$''',
]
regexes = [
    '''(?i)^true|false|null$''',
]

[[rules]]
id = "github-pat"
description = "GitHub Personal Access Token"
regex = '''ghp_[0-9a-zA-Z]{36}'''
entropy = 3
keywords = ["ghp_"]
EOF
)"

mkdir -p "$TMP/bin" "$TMP/stub-gitleaks"
# gh: logs its arguments, then serves $STUB_FIX/<key> (or <key>.err to stderr
# with exit 1), where <key> is the API path with / ? & = : turned into _. With
# --include it first prints a header block in gh's shape, carrying
# $STUB_REMAINING and $STUB_RESET. A run-list window with no fixture is empty.
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
path="" include=0
for a in "$@"; do
  case "$a" in repos/* | orgs/* | users/*) path="$a" ;; --include) include=1 ;; *) ;; esac
done
key="$(printf '%s' "$path" | tr '/?&=:' '_____')"
if [[ -f "$STUB_FIX/$key.err" ]]; then
  cat "$STUB_FIX/$key.err" >&2
  exit 1
fi
headers() {
  ((include)) || return 0
  printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\nX-Ratelimit-Remaining: %s\r\nX-Ratelimit-Reset: %s\r\n\r\n' \
    "${STUB_REMAINING:-5000}" "${STUB_RESET:-0}"
}
if [[ -f "$STUB_FIX/$key" ]]; then
  headers
  cat "$STUB_FIX/$key"
  exit 0
fi
if [[ "$path" == */actions/runs\?*created=* ]]; then
  headers
  echo '{"total_count":0,"workflow_runs":[]}'
  exit 0
fi
echo "gh: Not Found (HTTP 404)" >&2
exit 1
EOF
# sleep: logs its argument and returns at once.
cat >"$TMP/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"${STUB_SLEEP_LOG:-/dev/null}"
EOF
# gitleaks: reports $STUB_LEAK_FILE (relative to the scanned dir) as an
# unredacted github-pat hit when set, else nothing.
cat >"$TMP/stub-gitleaks/gitleaks" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == version ]]; then
  echo "${STUB_GITLEAKS_VERSION:-8.30.1}"
  exit 0
fi
report="" code=1 prev=""
for a in "$@"; do
  case "$prev" in -r) report="$a" ;; --exit-code) code="$a" ;; *) ;; esac
  prev="$a"
done
dir="$prev"
if [[ -z "${STUB_LEAK_FILE:-}" ]]; then
  echo '[]' >"$report"
  exit 0
fi
printf '[{"RuleID":"github-pat","Secret":"%s","Match":"token %s","Line":"x %s","File":"%s/%s","StartLine":3}]\n' \
  "$STUB_SECRET" "$STUB_SECRET" "$STUB_SECRET" "$dir" "$STUB_LEAK_FILE" >"$report"
exit "$code"
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/sleep" "$TMP/stub-gitleaks/gitleaks"

key() { printf '%s' "$1" | tr '/?&=:' '_____'; }
# runs_path <repo> <from> <to>: the run-list page 1 of one created window.
runs_path() { printf 'repos/o/%s/actions/runs?exclude_pull_requests=true&created=%s..%s&per_page=100&page=1' "$1" "$2" "$3"; }
# day_runs <repo> <YYYY-MM-DD>: the run-list page 1 of one UTC day.
day_runs() { runs_path "$1" "$2T00:00:00Z" "$2T23:59:59Z"; }
# fix <fixture-dir> <api-path> <content>
fix() { printf '%s\n' "$3" >"$1/$(key "$2")"; }
fix_err() { printf '%s\n' "$3" >"$1/$(key "$2").err"; }

# base_fixture <dir> <repo>: repo o/<repo> with every list empty.
base_fixture() {
  local d="$1" b="repos/o/$2" pages='per_page=100&page=1'
  mkdir -p "$d"
  fix "$d" "$b/actions/artifacts?$pages" '{"artifacts":[]}'
  fix "$d" "$b/releases?$pages" '[]'
  fix "$d" "$b/issues/comments?since=${SINCE}T00:00:00Z&$pages" '[]'
  fix "$d" "$b/pulls/comments?since=${SINCE}T00:00:00Z&$pages" '[]'
  fix "$d" "$b/actions/caches?$pages" '{"actions_caches":[]}'
  fix "$d" "$b/pulls?state=all&sort=updated&direction=desc&$pages" '[]'
  fix "$d" "$b" '{"private":false}'
  printf '%s\n' "$CONFIG_FIXTURE" >"$d/$(key "repos/gitleaks/gitleaks/contents/config/gitleaks.toml?ref=83d9cd684c87d95d656c1458ef04895a7f1cbd8e")"
}

# one_run <dir> <repo> <check-runs-json>: run 11 (attempt 1, suite 21),
# listed in the 2026-10-05 window.
one_run() {
  local d="$1" b="repos/o/$2"
  fix "$d" "$(day_runs "$2" 2026-10-05)" \
    '{"total_count":1,"workflow_runs":[{"id":11,"run_attempt":1,"check_suite_id":21,"created_at":"2026-10-05T10:00:00Z"}]}'
  fix "$d" "$b/check-suites/21/check-runs?filter=all&per_page=100&page=1" "$3"
}

# artifact_zip <dir> <repo> <member=content>...: artifact 5 ("a") since
# --since, whose zip holds each member; content \x00 marks a binary member.
artifact_zip() {
  local d="$1" b="repos/o/$2"
  shift 2
  fix "$d" "$b/actions/artifacts?per_page=100&page=1" \
    '{"artifacts":[{"id":5,"name":"a","expired":false,"created_at":"2026-10-05T00:00:00Z"}]}'
  "$PYTHON" -I - "$d/$(key "$b/actions/artifacts/5/zip")" "$@" <<'PY2' || fail "could not build the artifact zip"
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
for m in sys.argv[2:]:
    name, _, content = m.partition("=")
    z.writestr(name, content.replace("\\x00", "\x00").encode())
z.close()
PY2
}

# artifact_record <dir> <repo> <blob-content> [<victim>]: artifact 5
# ("x.dockerbuild") uploaded unzipped, so its download is a Docker build
# record's own bytes: a gzipped tar of an OCI layout. With <victim>, the tar
# also holds a symlink bin.strings.txt to it beside a binary bin.
BLOB=blobs/sha256/0000000000000000000000000000000000000000000000000000000000000001
artifact_record() {
  local d="$1" b="repos/o/$2"
  fix "$d" "$b/actions/artifacts?per_page=100&page=1" \
    '{"artifacts":[{"id":5,"name":"x.dockerbuild","expired":false,"created_at":"2026-10-05T00:00:00Z"}]}'
  "$PYTHON" -I - "$d/$(key "$b/actions/artifacts/5/zip")" "$BLOB" "$3" "${4:-}" <<'PY' || fail "could not build the build record"
import io, sys, tarfile
t = tarfile.open(sys.argv[1], "w:gz")
def add(name, data, mode=0o444):
    i = tarfile.TarInfo(name)
    i.size, i.mode = len(data), mode
    t.addfile(i, io.BytesIO(data))
add("oci-layout", b'{"imageLayoutVersion":"1.0.0"}')
add("index.json", b'{"schemaVersion":2,"manifests":[]}')
add(sys.argv[2], sys.argv[3].encode())
if sys.argv[4]:
    link = tarfile.TarInfo("bin.strings.txt")
    link.type, link.linkname = tarfile.SYMTYPE, sys.argv[4]
    t.addfile(link)
    add("bin", b"\x00\x01ATTACKER_CONTROLLED_LINE\x00")
t.close()
PY
}

# log_zip <dir> <repo> <text>: run 11's log archive holds build/1_step.txt.
log_zip() {
  local d="$1" src="$TMP/zipsrc-$RANDOM"
  mkdir -p "$src/build"
  printf 'line one\nline two\n%s\n' "$3" >"$src/build/1_step.txt"
  "$PYTHON" -I -m zipfile -c "$d/$(key "repos/o/$2/actions/runs/11/attempts/1/logs")" "$src/build" ||
    fail "could not build a fixture zip"
}

# sweep <gitleaks-bin-dir> <fixture> <out> [args...]: runs the sweep; sets RC,
# OUT (stdout and stderr) and LOG (the gh calls).
sweep() {
  local gl="$1" f="$2" out="$3"
  shift 3
  : >"$f.log"
  OUT="$(PATH="$TMP/bin:$gl:$PATH" STUB_FIX="$f" STUB_LOG="$f.log" \
    bash "$SUT" --owner o --since "$SINCE" --out "$out" "$@" 2>&1)" && RC=0 || RC=$?
  LOG="$(cat "$f.log")"
}

expect_rc() { if [[ "$RC" -eq "$2" ]]; then ok "$1"; else fail "$1: expected exit $2, got $RC; output: $OUT"; fi; }
expect_out() { if [[ "$OUT" == *"$2"* ]]; then ok "$1"; else fail "$1: no '$2' in output: $OUT"; fi; }
expect_no_value() {
  if [[ ! -s "$2/summary.md" || ! -s "$2/findings.json" ]]; then
    fail "$1: no report in $2"
  elif [[ "$OUT" == *"$body"* ]] || grep -qF "$body" "$2/summary.md" "$2/findings.json"; then
    fail "$1: the planted value appears in the output or the report"
  else
    ok "$1"
  fi
}
expect_get_only() {
  if [[ -n "$LOG" ]] && ! grep -qv -- '--method GET' <<<"$LOG"; then
    ok "$1"
  else
    fail "$1: a gh call without --method GET, or none: $LOG"
  fi
}

if [[ -z "$PYTHON" ]]; then
  fail "python3 is needed to build fixture zips"
  test_harness::report
  exit 1
fi

# --- A hit is reported by rule and location, never by value -----------------
F="$TMP/hit"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[{"id":31,"name":"build","output":{"title":"ok","summary":"","text":null}}]}'
log_zip "$F" r "token $PLANTED"
STUB_LEAK_FILE=r/logs/run-11-attempt-1/build/1_step.txt STUB_SECRET="$PLANTED" \
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-hit" --repo r
expect_rc "a hit exits 1" 1
expect_out "the hit names rule, location and line" '| github-pat | r/logs/run-11-attempt-1/build/1_step.txt | 3 |'
expect_no_value "an unredacted scanner report never reaches the output or the report" "$TMP/out-hit"
expect_get_only "every request is a GET"
first_window="$(grep -m 1 -o 'created=[^&]*' <<<"$LOG")"
if [[ "$first_window" == "created=${SINCE}T00:00:00Z..${SINCE}T23:59:59Z" ]] &&
  ! grep -q 'created=2026-09' <<<"$LOG"; then
  ok "runs are listed from the --since day on, one UTC day at a time"
else
  fail "first run window is '$first_window', or one before --since was listed: $LOG"
fi
if [[ ! -e "$TMP/out-hit/downloads" ]]; then ok "downloads are removed without --keep"; else fail "downloads left behind"; fi

# Same tree through the real pinned scanner, when this host has it.
if [[ "$(gitleaks version 2>/dev/null)" == 8.30.1 ]]; then
  sweep "$TMP/no-such-dir" "$F" "$TMP/out-real" --repo r
  expect_rc "the real scanner finds the planted token" 1
  expect_out "the real scanner's hit names rule and location" '| github-pat | r/logs/run-11-attempt-1/build/1_step.txt | 3 |'
  expect_no_value "the real scanner's hit is redacted" "$TMP/out-real"

  # A path the default config allowlists is still scanned.
  F="$TMP/allowlisted"
  base_fixture "$F" r
  artifact_zip "$F" r "node_modules/x/.env=token $PLANTED"
  sweep "$TMP/no-such-dir" "$F" "$TMP/out-allowlisted" --repo r
  expect_rc "a token under a default-allowlisted path is found" 1
  expect_out "the allowlisted-path hit names its location" '| github-pat | r/artifacts/5-a/node_modules/x/.env |'

  # A token inside a Docker build record artifact is found.
  F="$TMP/record-real"
  base_fixture "$F" r
  artifact_record "$F" r "token $PLANTED"
  sweep "$TMP/no-such-dir" "$F" "$TMP/out-record-real" --repo r
  expect_rc "the real scanner finds a token in a build record" 1
  expect_out "the build record hit names its blob" "| github-pat | r/artifacts/5-x.dockerbuild/$BLOB |"
else
  printf 'SKIP: gitleaks 8.30.1 not on PATH; the real-scanner cases did not run\n'
fi

# The scanner config is fetched at the pin; an unreadable one stops the sweep.
F="$TMP/noconfig"
base_fixture "$F" r
rm -f "$F/$(key "repos/gitleaks/gitleaks/contents/config/gitleaks.toml?ref=83d9cd684c87d95d656c1458ef04895a7f1cbd8e")"
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-noconfig" --repo r
expect_rc "an unreadable scanner config exits 3" 3

# --- The global path allowlist is stripped; rule allowlists are kept ---------
# strip_case <name> <global-allowlist-block>: sweeps a config holding the block
# and two rules, the first with its own path allowlist; sets TOML.
strip_case() {
  F="$TMP/strip-$1"
  base_fixture "$F" r
  printf '%s\n' 'title = "fixture"' "$2" "[[rules]]" 'id = "github-pat"' "regex = '''ghp_[0-9a-zA-Z]{36}'''" \
    "[[rules.allowlists]]" "paths = [" "    '''RULEPATH'''," "]" "[[rules]]" 'id = "second"' "regex = '''zz'''" \
    >"$F/$(key "repos/gitleaks/gitleaks/contents/config/gitleaks.toml?ref=83d9cd684c87d95d656c1458ef04895a7f1cbd8e")"
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-strip-$1" --repo r --keep
  TOML="$TMP/out-strip-$1/state/sweep.toml"
}
expect_stripped() {
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: expected exit 0, got $RC; output: $OUT"
  elif grep -q GLOBALPATH "$TOML"; then
    fail "$1: a global allowlist path survives: $(cat "$TOML")"
  elif ! grep -q RULEPATH "$TOML" || ! grep -q GLOBALREGEX "$TOML" ||
    [[ "$(grep -c '^\[\[rules\]\]' "$TOML")" -ne 2 ]]; then
    fail "$1: the strip removed more than the global paths: $(cat "$TOML")"
  else
    ok "$1"
  fi
}
strip_case multiline "$(printf '%s\n' '[allowlist]' 'paths = [' "    '''GLOBALPATH1'''," "    '''GLOBALPATH2'''," ']' \
  'regexes = [' "    '''GLOBALREGEX'''," ']' '[[allowlists]]' '  paths = [' "    '''GLOBALPATH3'''," '  ]')"
expect_stripped "a multi-line global paths list is removed and rule paths are kept"
strip_case opening "$(printf '%s\n' '[allowlist]' "paths = [ '''GLOBALPATH1'''," "    '''GLOBALPATH2'''," ']' \
  "regexes = ['''GLOBALREGEX''']")"
expect_stripped "a global paths list with an element on its opening line is removed"
strip_case oneline "$(printf '%s\n' '[allowlist]' "paths = ['''GLOBALPATH1''', '''GLOBALPATH2''']" "regexes = ['''GLOBALREGEX''']")"
expect_stripped "a one-line global paths list is removed"
strip_case comment "$(printf '%s\n' '[allowlist] # global' 'paths = [' "    '''GLOBALPATH1'''," ']' "regexes = ['''GLOBALREGEX''']")"
expect_stripped "a global allowlist header with a trailing comment is handled"

# A global paths key the strip does not remove stops the sweep before it starts.
strip_case quoted "$(printf '%s\n' '[allowlist]' "\"paths\" = ['''GLOBALPATH1''']" "regexes = ['''GLOBALREGEX''']")"
expect_rc "a global paths key left in place exits 3" 3
expect_out "the unstripped allowlist is named" 'still has a paths key'
if [[ "$LOG" != *actions/* ]]; then ok "nothing is swept with the allowlist in place"; else fail "swept with the allowlist: $LOG"; fi

# --- Check runs of every attempt are swept, not only the latest -------------
F="$TMP/attempts"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[{"id":30,"name":"build","output":{"title":"first attempt","summary":"","text":""}},{"id":31,"name":"build","output":{"title":"rerun","summary":"","text":""}}]}'
fix "$F" "repos/o/r/check-suites/21/check-runs?per_page=100&page=1" \
  '{"check_runs":[{"id":31,"name":"build","output":{"title":"rerun","summary":"","text":""}}]}'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-attempts" --repo r --keep
if grep -qF "check-run 30 build" "$TMP/out-attempts/downloads/r/check-runs/run-11.txt" 2>/dev/null; then
  ok "an earlier attempt's check run is swept"
else
  fail "check run 30 missing: $LOG"
fi

# --- A downloaded file is never overwritten by a strings(1) copy ------------
F="$TMP/sidecar"
base_fixture "$F" r
artifact_zip "$F" r 'payload=\x00BINARYCONTENTLINE\x00' 'payload.strings.txt=downloaded text'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-sidecar" --repo r --keep
if [[ "$(cat "$TMP/out-sidecar/downloads/r/artifacts/5-a/payload.strings.txt" 2>/dev/null)" == "downloaded text" ]]; then
  ok "a downloaded file named like a strings copy survives"
else
  fail "payload.strings.txt overwritten or missing"
fi
if grep -qF BINARYCONTENTLINE "$TMP/out-sidecar/downloads/r/strings/artifacts/5-a/payload.strings.txt" 2>/dev/null; then
  ok "the binary's strings copy is kept apart from the downloads"
else
  fail "no strings copy of the binary under r/strings"
fi

# --- An undownloadable log is a gap, not a pass -----------------------------
F="$TMP/gone"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[]}'
fix_err "$F" "repos/o/r/actions/runs/11/attempts/1/logs" 'gh: Server Error (HTTP 502)'
fix "$F" "orgs/o/repos?type=public&per_page=100&page=1" '[{"name":"r","private":false},{"name":"p","private":true}]'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-gone"
expect_rc "gaps without hits exit 2" 2
expect_out "the undownloadable log is listed under GAPS" '- r: logs: run 11 attempt 1: gh: Server Error (HTTP 502)'
expect_out "no hits is stated" $'## Hits (0)\n\nNone'
if [[ "$LOG" != *repos/o/p/* ]]; then ok "the default listing sweeps public repos only"; else fail "private repo p was swept: $LOG"; fi

# Control characters in API text never reach the report.
F="$TMP/ctrl"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[]}'
fix_err "$F" "repos/o/r/actions/runs/11/attempts/1/logs" $'gh: \e[2Jbad (HTTP 502)'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-ctrl" --repo r
if ! grep -q $'\e' "$TMP/out-ctrl/summary.md"; then ok "control characters are stripped from the report"; else fail "ESC in the report"; fi

# A skipped run's empty log archive holds nothing to read: no gap.
F="$TMP/empty"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[]}'
printf 'PK\005\006%018d' 0 | tr 0 '\000' >"$F/$(key "repos/o/r/actions/runs/11/attempts/1/logs")"
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-empty" --repo r
expect_rc "an empty log archive exits 0" 0
expect_out "an empty log archive is no gap" $'## GAPS (0)\n\nNone'

# A skipped run is counted, and its logs and check runs are not fetched.
F="$TMP/skipped"
base_fixture "$F" r
fix "$F" "$(day_runs r 2026-10-06)" \
  '{"total_count":1,"workflow_runs":[{"id":61,"run_attempt":1,"check_suite_id":71,"conclusion":"skipped","created_at":"2026-10-06T10:00:00Z"}]}'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-skipped" --repo r
expect_rc "a skipped run alone exits 0" 0
expect_out "skipped runs have their own report line" 'skipped runs (no job ran): 1;'
if [[ "$LOG" != *runs/61/* && "$LOG" != *check-suites/71/* ]]; then
  ok "a skipped run's logs and check runs are not fetched"
else
  fail "skipped run fetched: $LOG"
fi

# A re-run whose latest attempt was skipped still has its earlier attempts read.
F="$TMP/rerun"
base_fixture "$F" r
fix "$F" "$(day_runs r 2026-10-06)" \
  '{"total_count":1,"workflow_runs":[{"id":11,"run_attempt":2,"check_suite_id":21,"conclusion":"skipped","created_at":"2026-10-06T10:00:00Z"}]}'
fix "$F" "repos/o/r/check-suites/21/check-runs?filter=all&per_page=100&page=1" '{"check_runs":[]}'
log_zip "$F" r "token $PLANTED"
printf 'PK\005\006%018d' 0 | tr 0 '\000' >"$F/$(key "repos/o/r/actions/runs/11/attempts/2/logs")"
STUB_LEAK_FILE=r/logs/run-11-attempt-1/build/1_step.txt STUB_SECRET="$PLANTED" \
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-rerun" --repo r --keep
if grep -qF "$PLANTED" "$TMP/out-rerun/downloads/r/logs/run-11-attempt-1/build/1_step.txt" 2>/dev/null &&
  [[ "$LOG" == *check-suites/21/check-runs* ]]; then
  ok "a skipped re-run's earlier attempt and check runs are read"
else
  fail "attempt 1 of a skipped re-run not read: $LOG"
fi
expect_out "a skipped re-run is not counted as a skipped run" 'skipped runs (no job ran): 0;'
if [[ "$(gitleaks version 2>/dev/null)" == 8.30.1 ]]; then
  sweep "$TMP/no-such-dir" "$F" "$TMP/out-rerun-real" --repo r
  expect_out "the real scanner finds the token in a skipped re-run's first attempt" \
    '| github-pat | r/logs/run-11-attempt-1/build/1_step.txt | 3 |'
fi

# A run listed in two windows is swept once.
F="$TMP/dupe"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[]}'
fix "$F" "$(day_runs r 2026-10-06)" \
  '{"total_count":1,"workflow_runs":[{"id":11,"run_attempt":1,"check_suite_id":21,"created_at":"2026-10-05T10:00:00Z"}]}'
log_zip "$F" r "nothing secret here"
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-dupe" --repo r
expect_out "a run listed twice is counted once" '| r | 1 | 1 |'
if [[ "$(grep -c 'runs/11/attempts/1/logs' <<<"$LOG")" -eq 1 ]]; then ok "a run listed twice is fetched once"; else fail "run 11 fetched more than once: $LOG"; fi

# Expired logs (HTTP 410) are served to nobody: listed apart, exit 0.
F="$TMP/expired"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[]}'
fix_err "$F" "repos/o/r/actions/runs/11/attempts/1/logs" 'gh: Gone (HTTP 410)'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-expired" --repo r
expect_rc "expired logs alone exit 0" 0
expect_out "expired logs are counted as unreadable by design" '- r: logs: run 11 attempt 1: logs expired or deleted (HTTP 410)'

# --- A filtered list keeps paging past a page its filter thins out -----------
F="$TMP/paging"
base_fixture "$F" r
humans="$(jq -cn '[range(100) | {id: ., user: {login: "h", type: "User"}, body: "hi", html_url: "u"}]')"
fix "$F" "repos/o/r/issues/comments?since=${SINCE}T00:00:00Z&per_page=100&page=1" "$humans"
fix "$F" "repos/o/r/issues/comments?since=${SINCE}T00:00:00Z&per_page=100&page=2" \
  "[{\"id\":500,\"user\":{\"login\":\"b[bot]\",\"type\":\"Bot\"},\"body\":\"token $PLANTED\",\"html_url\":\"u\"}]"
STUB_LEAK_FILE=r/bot-comments/issues.txt STUB_SECRET="$PLANTED" \
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-paging" --repo r --keep
expect_rc "a bot comment on page 2 is swept" 1
if grep -qF "comment 500 by b[bot]" "$TMP/out-paging/downloads/r/bot-comments/issues.txt"; then
  ok "page 2 of a filtered list is fetched"
else
  fail "page 2 bot comment missing: $LOG"
fi

# --- Bot review bodies on pull requests updated since --since are swept ------
F="$TMP/reviews"
base_fixture "$F" r
fix "$F" "repos/o/r/pulls?state=all&sort=updated&direction=desc&per_page=100&page=1" \
  '[{"number":7,"updated_at":"2026-10-05T00:00:00Z"},{"number":3,"updated_at":"2026-09-01T00:00:00Z"}]'
fix "$F" "repos/o/r/pulls/7/reviews?per_page=100&page=1" \
  '[{"id":70,"user":{"login":"b[bot]","type":"Bot"},"body":"bot review","html_url":"u"},{"id":71,"user":{"login":"h","type":"User"},"body":"human review","html_url":"u"}]'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-reviews" --repo r --keep
expect_rc "bot reviews alone exit 0" 0
if grep -qF "review 70 by b[bot]" "$TMP/out-reviews/downloads/r/bot-comments/reviews.txt" &&
  ! grep -qF "review 71" "$TMP/out-reviews/downloads/r/bot-comments/reviews.txt"; then
  ok "bot review bodies are swept and human ones are not"
else
  fail "review bodies wrong: $(cat "$TMP/out-reviews/downloads/r/bot-comments/reviews.txt")"
fi
if [[ "$LOG" != *pulls/3/reviews* ]]; then ok "a pull request before --since is not fetched"; else fail "pull 3 reviews fetched: $LOG"; fi

# --- A symlink in an archive is deleted, never written through ---------------
F="$TMP/symlink"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[]}'
printf 'untouched\n' >"$TMP/victim"
"$PYTHON" -I - "$F/$(key "repos/o/r/actions/runs/11/attempts/1/logs")" "$TMP/victim" <<'PY' || fail "could not build the symlink zip"
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
link = zipfile.ZipInfo("bin.strings.txt")
link.create_system = 3
link.external_attr = (0o120777 << 16)
z.writestr(link, sys.argv[2])
z.writestr("bin", b"\x00\x01ATTACKER_CONTROLLED_LINE\x00")
z.close()
PY
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-symlink" --repo r
if [[ "$(cat "$TMP/victim")" == untouched ]]; then ok "a symlink in an archive is not written through"; else fail "victim overwritten: $(cat "$TMP/victim")"; fi

# --- A Docker build record artifact (a gzipped tar, not a zip) is scanned ----
F="$TMP/record"
base_fixture "$F" r
artifact_record "$F" r "token $PLANTED"
STUB_LEAK_FILE="r/artifacts/5-x.dockerbuild/$BLOB" STUB_SECRET="$PLANTED" \
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-record" --repo r --keep
expect_rc "a hit in a build record exits 1" 1
expect_out "a build record is not a gap" $'## GAPS (0)\n\nNone'
if grep -qF "token $PLANTED" "$TMP/out-record/downloads/r/artifacts/5-x.dockerbuild/$BLOB" 2>/dev/null; then
  ok "a build record's blobs are extracted for the scan"
else
  fail "build record blob missing: $(find "$TMP/out-record/downloads/r/artifacts" 2>&1)"
fi

F="$TMP/record-symlink"
base_fixture "$F" r
printf 'untouched\n' >"$TMP/victim2"
artifact_record "$F" r "nothing secret here" "$TMP/victim2"
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-record-symlink" --repo r --keep
expect_rc "a build record with a symlink sweeps clean" 0
if [[ "$(cat "$TMP/victim2")" == untouched ]]; then ok "a symlink in a build record is not written through"; else fail "victim2 overwritten: $(cat "$TMP/victim2")"; fi
if [[ ! -L "$TMP/out-record-symlink/downloads/r/artifacts/5-x.dockerbuild/bin.strings.txt" ]]; then
  ok "a symlink in a build record is deleted"
else
  fail "the build record's symlink survives"
fi

# record_tar <dir> <mode> <member:mode[:content]>...: artifact 5 ("x.dockerbuild")
# is a tar written with tarfile mode <mode> ("w:xz", "w:gz"); a member whose
# name ends in / is a directory.
record_tar() {
  local d="$1" mode="$2"
  shift 2
  fix "$d" "repos/o/r/actions/artifacts?per_page=100&page=1" \
    '{"artifacts":[{"id":5,"name":"x.dockerbuild","expired":false,"created_at":"2026-10-05T00:00:00Z"}]}'
  "$PYTHON" -I - "$d/$(key "repos/o/r/actions/artifacts/5/zip")" "$mode" "$@" <<'PY' || fail "could not build the tar"
import io, sys, tarfile
t = tarfile.open(sys.argv[1], sys.argv[2])
for m in sys.argv[3:]:
    name, mode, *rest = m.split(":", 2)
    i = tarfile.TarInfo(name.rstrip("/"))
    i.mode = int(mode, 8)
    if name.endswith("/"):
        i.type = tarfile.DIRTYPE
        t.addfile(i)
    else:
        data = (rest[0] if rest else "").encode()
        i.size = len(data)
        t.addfile(i, io.BytesIO(data))
t.close()
PY
}

# A tar compressed other than with gzip is never handed to tar, which would
# decompress it without a bound: it is kept as one file and scanned as bytes.
F="$TMP/record-xz"
base_fixture "$F" r
record_tar "$F" w:xz "inner.txt:644:token $PLANTED"
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-record-xz" --repo r --keep
expect_rc "an xz tar sweeps without a gap" 0
x="$TMP/out-record-xz/downloads/r/artifacts/5-x.dockerbuild"
if [[ -f "$x/5-x.dockerbuild" && ! -e "$x/inner.txt" ]]; then
  ok "an xz tar is kept as one file, not extracted"
else
  fail "an xz tar was extracted or lost: $(find "$x" 2>&1)"
fi

# A tar that fails partway is cleaned up: no read-only directory or member is
# left behind once the sweep removes its downloads.
F="$TMP/record-partial"
base_fixture "$F" r
record_tar "$F" w:gz "d/:555" "d/f:444:partial" "../x:644:escape"
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-record-partial" --repo r
expect_rc "a tar that fails partway is a gap" 2
expect_out "the failed tar is named" "artifact tar did not extract"
if [[ ! -e "$TMP/out-record-partial/downloads" && ! -e "$TMP/x" && ! -e "$TMP/out-record-partial/downloads/r/x" ]]; then
  ok "a failed tar leaves nothing on disk"
else
  fail "left on disk: $(find "$TMP/out-record-partial/downloads" "$TMP/x" 2>&1)"
fi

# --- A --repo that is not public is refused ----------------------------------
F="$TMP/private"
base_fixture "$F" r
fix "$F" "repos/o/r" '{"private":true}'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-private" --repo r
expect_rc "a private --repo exits 3" 3
if [[ "$(wc -l <<<"$LOG")" -eq 1 ]]; then ok "nothing of a private repo is swept"; else fail "requests after the public check: $LOG"; fi

# --- Nothing unread and nothing found is a clean exit ------------------------
F="$TMP/clean"
base_fixture "$F" r
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-clean" --repo r --keep
expect_rc "no hits and no gaps exit 0" 0
expect_out "no gaps is stated" $'## GAPS (0)\n\nNone'
if [[ -d "$TMP/out-clean/downloads/r" ]]; then ok "--keep keeps the downloads"; else fail "--keep removed the downloads"; fi

# --- What the API serves to nobody is listed apart and exits 0 --------------
F="$TMP/by-design"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[{"id":31,"name":"build","output":{"title":"ok","summary":"","text":null}},{"id":32,"name":"lint","output":{}}]}'
log_zip "$F" r "nothing secret here"
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-summaries" --repo r
expect_rc "unread step summaries alone exit 0" 0
expect_out "no gaps beside unread step summaries" $'## GAPS (0)\n\nNone'
expect_out "the step summaries are counted as unreadable by design" \
  $'## Unreadable by design (1)\n\nThe API serves these to nobody; they do not change the exit code.\n\n- r: step-summaries: 2 jobs'

F="$TMP/cache"
base_fixture "$F" r
fix "$F" "repos/o/r/actions/caches?per_page=100&page=1" '{"actions_caches":[{"id":1,"key":"k1"},{"id":2,"key":"k2"}]}'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-cache" --repo r
expect_rc "cache entries alone exit 0" 0
expect_out "the caches are counted as unreadable by design" '- r: caches: 2 entries listed'

# --- A run window listed short of its total_count is a gap ------------------
F="$TMP/short"
base_fixture "$F" r
fix "$F" "$(day_runs r 2026-10-03)" '{"total_count":3,"workflow_runs":[]}'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-short" --repo r
expect_rc "a short run window exits 2" 2
expect_out "the short window is listed under GAPS" \
  '- r: logs: run list for 2026-10-03T00:00:00Z..2026-10-03T23:59:59Z: listed 0 of total_count 3'

# A window over the 1,000-result cap is halved, and each half is listed.
F="$TMP/split"
base_fixture "$F" r
fix "$F" "$(day_runs r 2026-10-04)" '{"total_count":1500,"workflow_runs":[]}'
fix "$F" "$(runs_path r 2026-10-04T00:00:00Z 2026-10-04T11:59:59Z)" \
  '{"total_count":1,"workflow_runs":[{"id":41,"run_attempt":1,"check_suite_id":51,"created_at":"2026-10-04T01:00:00Z"}]}'
fix "$F" "$(runs_path r 2026-10-04T12:00:00Z 2026-10-04T23:59:59Z)" \
  '{"total_count":1,"workflow_runs":[{"id":42,"run_attempt":1,"check_suite_id":52,"created_at":"2026-10-04T13:00:00Z"}]}'
fix "$F" "repos/o/r/check-suites/51/check-runs?filter=all&per_page=100&page=1" '{"check_runs":[]}'
fix "$F" "repos/o/r/check-suites/52/check-runs?filter=all&per_page=100&page=1" '{"check_runs":[]}'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-split" --repo r
expect_out "both halves of an over-cap window are swept" '| r | 2 |'
if [[ "$LOG" == *runs/41/attempts/1/logs* && "$LOG" == *runs/42/attempts/1/logs* &&
  "$LOG" != *2026-10-04T00:00:00Z..2026-10-04T23:59:59Z\&per_page=100\&page=2* ]]; then
  ok "an over-cap window is not paged; its halves are"
else
  fail "split window requests wrong: $LOG"
fi

# --- Below the reserve, the sweep waits for the reset ------------------------
F="$TMP/reserve"
base_fixture "$F" r
: >"$F.sleep"
STUB_REMAINING=100 STUB_RESET="$(($(date +%s) + 30))" STUB_SLEEP_LOG="$F.sleep" \
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-reserve" --repo r --interval 0
first_sleep="$(head -n 1 "$F.sleep")"
if [[ "$first_sleep" =~ ^[0-9]+$ ]] && ((first_sleep > 0 && first_sleep <= 31)); then
  ok "under the reserve, the sweep sleeps until the reset"
else
  fail "no sleep until the reset under the reserve: '$(cat "$F.sleep")'"
fi
expect_out "the report states the waits" 'Reserve: 1500; waited for the reset'
: >"$F.sleep"
STUB_REMAINING=1500 STUB_RESET="$(($(date +%s) + 30))" STUB_SLEEP_LOG="$F.sleep" \
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-reserve-at" --repo r --interval 0
if [[ ! -s "$F.sleep" ]]; then ok "at the reserve, the sweep does not wait"; else fail "slept at the reserve: $(cat "$F.sleep")"; fi
STUB_REMAINING=100 STUB_RESET="$(($(date +%s) + 30))" STUB_SLEEP_LOG="$F.sleep" \
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-reserve-zero" --repo r --reserve 0 --interval 0
if [[ ! -s "$F.sleep" ]]; then ok "--reserve 0 never waits"; else fail "slept with --reserve 0: $(cat "$F.sleep")"; fi
STUB_REMAINING=100 STUB_RESET="$(($(date +%s) - 30))" STUB_SLEEP_LOG="$F.sleep" \
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-reserve-past" --repo r --interval 0
if [[ ! -s "$F.sleep" ]]; then ok "a reset already past is not waited for"; else fail "slept for a past reset: $(cat "$F.sleep")"; fi

# --- The first rate-limit error stops every later request -------------------
F="$TMP/limit"
base_fixture "$F" r
base_fixture "$F" s
fix_err "$F" "$(day_runs r "$SINCE")" 'gh: API rate limit exceeded for user ID 1. (HTTP 403)'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-limit" --repo r --repo s
expect_rc "a rate-limit stop exits 2" 2
expect_out "the stop is reported as a gap" 'stopped mid-repo: rate limit on GET'
expect_out "the repo after the stop is a gap" '- s: all: not swept'
if [[ "$(tail -n 1 <<<"$LOG")" == *actions/runs* ]]; then ok "no request follows the rate-limit error"; else fail "requests after the limit: $LOG"; fi

# A secondary-limit 403 stops the sweep the same way.
F="$TMP/secondary"
base_fixture "$F" r
base_fixture "$F" s
fix_err "$F" "$(day_runs r "$SINCE")" \
  'gh: You have exceeded a secondary rate limit. Please wait a few minutes before you try again. (HTTP 403)'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-secondary" --repo r --repo s
expect_rc "a secondary-limit stop exits 2" 2
expect_out "the secondary-limit stop is reported as a gap" 'stopped mid-repo: rate limit on GET'
expect_out "the repo after a secondary-limit stop is a gap" '- s: all: not swept'
if [[ "$(tail -n 1 <<<"$LOG")" == *actions/runs* ]]; then
  ok "no request follows a secondary-limit error"
else
  fail "requests after the secondary limit: $LOG"
fi

# --- Requests start at least --interval seconds apart ------------------------
# The stub sleep logs each spacing wait and returns at once.
F="$TMP/interval"
base_fixture "$F" r
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-interval-default" --repo r
expect_out "the default interval is 1 second" 'Interval: 1s between request starts.'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-interval-frac" --repo r --interval .5
expect_out "an interval with no whole part is accepted" 'Interval: .5s between request starts.'
: >"$F.sleep"
STUB_SLEEP_LOG="$F.sleep" sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-interval" --repo r --interval 1.5
expect_rc "a sweep with --interval 1.5 exits 0" 0
expect_out "the report states the interval" 'Interval: 1.5s between request starts.'
if [[ -s "$F.sleep" ]] && awk '!($1 > 0 && $1 <= 1.5) { bad = 1 } END { exit bad }' "$F.sleep"; then
  ok "each spacing wait is above 0 and at most the interval"
else
  fail "spacing waits wrong for --interval 1.5: '$(cat "$F.sleep")'"
fi

# Two requests through a stub gh that stamps its start, with the real sleep:
# the second starts at least the interval after the first. Process start-up
# jitter between the two stub runs is allowed 100 ms. Interval 0 is the control.
mkdir -p "$TMP/timed-bin"
cat >"$TMP/timed-bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${EPOCHREALTIME/[.,]/}" >>"$STUB_TIME_LOG"
printf 'HTTP/2.0 200 OK\r\n\r\n{}\n'
EOF
chmod +x "$TMP/timed-bin/gh"
# two_requests <interval>: prints the microseconds between the two stub starts.
two_requests() {
  local log="$TMP/timed-$1.log"
  : >"$log"
  (
    PATH="$TMP/timed-bin:$PATH"
    STUB_TIME_LOG="$log"
    export STUB_TIME_LOG
    # shellcheck source=credential-sweep.sh
    . "$SUT"
    STATE="$TMP/timed-state-$1"
    mkdir -p "$STATE"
    set_interval "$1"
    api_get "$STATE/a" repos/o/r
    api_get "$STATE/b" repos/o/r
  )
  awk 'NR == 1 { a = $1 } NR == 2 { print $1 - a }' "$log"
}
gap_us="$(two_requests 0.6)"
if [[ "$gap_us" =~ ^[0-9]+$ ]] && ((gap_us >= 500000)); then
  ok "a second request starts at least the interval after the first"
else
  fail "requests ${gap_us:-?} us apart with --interval 0.6"
fi
gap_us="$(two_requests 0)"
if [[ "$gap_us" =~ ^[0-9]+$ ]] && ((gap_us < 500000)); then
  ok "with interval 0 the two requests are not spaced (control)"
else
  fail "requests ${gap_us:-?} us apart with interval 0"
fi

# --- Could not start ---------------------------------------------------------
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-bogus" --bogus
expect_rc "an unknown option exits 3" 3
expect_out "usage describes --keep" '--keep     keep the downloads'
expect_out "usage describes --reserve" '--reserve  REST requests left for other work'
expect_out "usage describes --interval" '--interval minimum seconds'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-reserve-bad" --repo r --reserve lots
expect_rc "a non-numeric --reserve exits 3" 3
for bad in fast -1 1. . 1,5; do
  sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-interval-bad" --repo r --interval "$bad"
  expect_rc "--interval $bad exits 3" 3
  expect_out "--interval $bad prints a usage line" "usage: --interval SECONDS"
  if [[ -z "$LOG" ]]; then ok "--interval $bad requests nothing"; else fail "requests with --interval $bad: $LOG"; fi
done
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-usage" --since 2026-13-45
expect_rc "a malformed --since exits 3" 3
STUB_GITLEAKS_VERSION=8.0.0 sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-version" --repo r
expect_rc "a gitleaks other than the pin exits 3" 3
if [[ -z "$LOG" ]]; then ok "nothing is requested before the preconditions hold"; else fail "requests before start: $LOG"; fi

test_harness::report
