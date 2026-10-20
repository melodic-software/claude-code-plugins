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

mkdir -p "$TMP/bin" "$TMP/stub-gitleaks"
# gh: logs its arguments, then serves $STUB_FIX/<key> (or <key>.err to stderr
# with exit 1), where <key> is the API path with / ? & = : turned into _.
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
path=""
for a in "$@"; do
  case "$a" in repos/* | orgs/* | users/*) path="$a" ;; *) ;; esac
done
key="$(printf '%s' "$path" | tr '/?&=:' '_____')"
if [[ -f "$STUB_FIX/$key.err" ]]; then
  cat "$STUB_FIX/$key.err" >&2
  exit 1
fi
if [[ -f "$STUB_FIX/$key" ]]; then
  cat "$STUB_FIX/$key"
  exit 0
fi
echo "gh: Not Found (HTTP 404)" >&2
exit 1
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
chmod +x "$TMP/bin/gh" "$TMP/stub-gitleaks/gitleaks"

key() { printf '%s' "$1" | tr '/?&=:' '_____'; }
# fix <fixture-dir> <api-path> <content>
fix() { printf '%s\n' "$3" >"$1/$(key "$2")"; }
fix_err() { printf '%s\n' "$3" >"$1/$(key "$2").err"; }

# base_fixture <dir> <repo>: repo o/<repo> with every list empty.
base_fixture() {
  local d="$1" b="repos/o/$2" pages='per_page=100&page=1'
  mkdir -p "$d"
  fix "$d" "$b/actions/runs?exclude_pull_requests=true&$pages" '{"workflow_runs":[]}'
  fix "$d" "$b/actions/artifacts?$pages" '{"artifacts":[]}'
  fix "$d" "$b/releases?$pages" '[]'
  fix "$d" "$b/issues/comments?since=${SINCE}T00:00:00Z&$pages" '[]'
  fix "$d" "$b/pulls/comments?since=${SINCE}T00:00:00Z&$pages" '[]'
  fix "$d" "$b/actions/caches?$pages" '{"actions_caches":[]}'
}

# one_run <dir> <repo> <check-runs-json>: run 11 (attempt 1, suite 21) since
# --since, plus run 99 from before it, whose logs must never be requested.
one_run() {
  local d="$1" b="repos/o/$2"
  fix "$d" "$b/actions/runs?exclude_pull_requests=true&per_page=100&page=1" \
    '{"workflow_runs":[{"id":11,"run_attempt":1,"check_suite_id":21,"created_at":"2026-10-05T10:00:00Z"},{"id":99,"run_attempt":1,"check_suite_id":98,"created_at":"2026-09-01T10:00:00Z"}]}'
  fix "$d" "$b/check-suites/21/check-runs?per_page=100&page=1" "$3"
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
if [[ "$LOG" != *runs/99/* ]]; then ok "a run before --since is not fetched"; else fail "run 99 was fetched: $LOG"; fi
if [[ ! -e "$TMP/out-hit/downloads" ]]; then ok "downloads are removed without --keep"; else fail "downloads left behind"; fi

# Same tree through the real pinned scanner, when this host has it.
if [[ "$(gitleaks version 2>/dev/null)" == 8.30.1 ]]; then
  sweep "$TMP/no-such-dir" "$F" "$TMP/out-real" --repo r
  expect_rc "the real scanner finds the planted token" 1
  expect_out "the real scanner's hit names rule and location" '| github-pat | r/logs/run-11-attempt-1/build/1_step.txt | 3 |'
  expect_no_value "the real scanner's hit is redacted" "$TMP/out-real"
else
  printf 'SKIP: gitleaks 8.30.1 not on PATH; the real-scanner case did not run\n'
fi

# --- An undownloadable log is a gap, not a pass -----------------------------
F="$TMP/gone"
base_fixture "$F" r
one_run "$F" r '{"check_runs":[]}'
fix_err "$F" "repos/o/r/actions/runs/11/attempts/1/logs" 'gh: Not Found (HTTP 410)'
fix "$F" "orgs/o/repos?type=public&per_page=100&page=1" '[{"name":"r","private":false},{"name":"p","private":true}]'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-gone"
expect_rc "gaps without hits exit 2" 2
expect_out "the undownloadable log is listed under GAPS" '- r: logs: run 11 attempt 1: gh: Not Found (HTTP 410)'
expect_out "no hits is stated" $'## Hits (0)\n\nNone'
if [[ "$LOG" != *repos/o/p/* ]]; then ok "the default listing sweeps public repos only"; else fail "private repo p was swept: $LOG"; fi

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

# --- The first rate-limit error stops every later request -------------------
F="$TMP/limit"
base_fixture "$F" r
base_fixture "$F" s
fix_err "$F" "repos/o/r/actions/runs?exclude_pull_requests=true&per_page=100&page=1" \
  'gh: API rate limit exceeded for user ID 1. (HTTP 403)'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-limit" --repo r --repo s
expect_rc "a rate-limit stop exits 2" 2
expect_out "the stop is reported as a gap" 'stopped mid-repo: rate limit on GET'
expect_out "the repo after the stop is a gap" '- s: all: not swept'
if [[ "$(wc -l <<<"$LOG")" -eq 1 ]]; then ok "no request follows the rate-limit error"; else fail "requests after the limit: $LOG"; fi

# --- Could not start ---------------------------------------------------------
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-usage" --since 2026-13-45
expect_rc "a malformed --since exits 3" 3
STUB_GITLEAKS_VERSION=8.0.0 sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-version" --repo r
expect_rc "a gitleaks other than the pin exits 3" 3
if [[ -z "$LOG" ]]; then ok "nothing is requested before the preconditions hold"; else fail "requests before start: $LOG"; fi

test_harness::report
