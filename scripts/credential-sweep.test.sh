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
  fix "$d" "$b/pulls?state=all&sort=updated&direction=desc&$pages" '[]'
  fix "$d" "$b" '{"private":false}'
  printf '%s\n' "$CONFIG_FIXTURE" >"$d/$(key "repos/gitleaks/gitleaks/contents/config/gitleaks.toml?ref=83d9cd684c87d95d656c1458ef04895a7f1cbd8e")"
}

# one_run <dir> <repo> <check-runs-json>: run 11 (attempt 1, suite 21) since
# --since, plus run 99 from before it, whose logs must never be requested.
one_run() {
  local d="$1" b="repos/o/$2"
  fix "$d" "$b/actions/runs?exclude_pull_requests=true&per_page=100&page=1" \
    '{"workflow_runs":[{"id":11,"run_attempt":1,"check_suite_id":21,"created_at":"2026-10-05T10:00:00Z"},{"id":99,"run_attempt":1,"check_suite_id":98,"created_at":"2026-09-01T10:00:00Z"}]}'
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

  # A path the default config allowlists is still scanned.
  F="$TMP/allowlisted"
  base_fixture "$F" r
  artifact_zip "$F" r "node_modules/x/.env=token $PLANTED"
  sweep "$TMP/no-such-dir" "$F" "$TMP/out-allowlisted" --repo r
  expect_rc "a token under a default-allowlisted path is found" 1
  expect_out "the allowlisted-path hit names its location" '| github-pat | r/artifacts/5-a/node_modules/x/.env |'
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
if [[ "$(tail -n 1 <<<"$LOG")" == *actions/runs* ]]; then ok "no request follows the rate-limit error"; else fail "requests after the limit: $LOG"; fi

# --- Could not start ---------------------------------------------------------
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-bogus" --bogus
expect_rc "an unknown option exits 3" 3
expect_out "usage describes --keep" '--keep   keep the downloads'
sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-usage" --since 2026-13-45
expect_rc "a malformed --since exits 3" 3
STUB_GITLEAKS_VERSION=8.0.0 sweep "$TMP/stub-gitleaks" "$F" "$TMP/out-version" --repo r
expect_rc "a gitleaks other than the pin exits 3" 3
if [[ -z "$LOG" ]]; then ok "nothing is requested before the preconditions hold"; else fail "requests before start: $LOG"; fi

test_harness::report
