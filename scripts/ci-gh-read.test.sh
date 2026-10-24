#!/usr/bin/env bash
# Runs the `Write the rate-limit-aware read helper` step body of
# .github/workflows/pr-require-checks.yml's ci-status, then calls the gh_read
# function it writes, under bash -e, against stub `gh`, `sleep` and `date`.
#
# gh_read runs `gh api` through the api-budget wrapper, whose rate guard stops
# a pool until its reset on a rate-limited response: retry-after seconds, else
# x-ratelimit-reset while remaining is 0, else a guess: the documented minute
# for a secondary limit, an hour for any other. gh_read then waits once, one
# second past a reset a header gave, and reads again; a guessed stop gets no
# wait, so it fails the read at once. Nothing is sent while the pool is
# stopped, a probe included. A wait that would end past the
# deadline the step sets (the job's timeout less a margin, from when the step
# runs) fails the read at once naming the reset. Any other failure returns at
# once.
# test-scope: .github/workflows/pr-require-checks.yml
# shellcheck disable=SC2016 # the step snippets are literal
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

if ! ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" budget; then
  fail "no working 'Write the rate-limit-aware read helper' step, or no GH_READ_* env, in $WORKFLOW"
  test_harness::report
  exit 1
fi

job="$(awk '/^  ci-status:$/ { on = 1 } on && /^  [a-z-]+:$/ && !/ci-status/ { exit } on { print }' "$WORKFLOW")"
timeout="$(sed -nE 's/^    timeout-minutes: ([0-9]+)$/\1/p' <<<"$job")"
job_seconds="$(sed -nE 's/^      GH_READ_JOB_SECONDS: ([0-9]+)$/\1/p' <<<"$job")"
margin="$(sed -nE 's/^      GH_READ_MARGIN_SECONDS: ([0-9]+)$/\1/p' <<<"$job")"
if [[ -n "$timeout" && "$job_seconds" == $((timeout * 60)) ]]; then
  ok "GH_READ_JOB_SECONDS ($job_seconds) is ci-status's timeout-minutes ($timeout) in seconds"
else
  fail "GH_READ_JOB_SECONDS '$job_seconds' is not ci-status's timeout-minutes '$timeout' in seconds"
fi
if [[ -n "$margin" && "$margin" -ge 240 && "$margin" -lt "${job_seconds:-0}" ]]; then
  ok "the ${margin}s margin leaves room for aggregate-results' 202 s of waits and the setup"
else
  fail "the margin '$margin' does not leave room for the steps after a wait"
fi
want=$(($(date +%s) + job_seconds - margin))
got="$(cat "$TMP_ROOT/gh-read.deadline")"
if [[ "$got" -ge $((want - 5)) && "$got" -le "$want" ]]; then
  ok "the step sets the deadline at its start plus the timeout less the margin"
else
  fail "the step set the deadline '$got', want about '$want'"
fi
if [[ "$job" != *"rate-limit-wait-seconds:"* ]]; then
  ok "the pinned composites keep their own rate-limit-wait-seconds default"
else
  fail "ci-status passes rate-limit-wait-seconds to a composite, which the unchanged timeout does not hold"
fi
first="$(grep -m1 '^      - name: ' <<<"$job")"
if [[ "$first" == "      - name: Write the rate-limit-aware read helper" ]]; then
  ok "the helper is ci-status's first step, so no failure before it skips it"
else
  fail "ci-status's first step is '$first', not the helper"
fi
# Every step that reads through gh_read sources it first.
while IFS= read -r name; do
  body="$(awk -v name="      - name: $name" '$0 == name { on = 1; next } on && /^      - / { exit } on { print }' <<<"$job")"
  if [[ "$body" == *$'        run: |\n          . "$RUNNER_TEMP/gh-read.sh"\n'* ]]; then
    ok "'$name' sources gh_read before its reads"
  else
    fail "'$name' calls gh_read without sourcing it first"
  fi
done < <(awk '/^      - name: / { name = substr($0, 15) } /gh_read [-"]/ && name != "Write the rate-limit-aware read helper" { print name }' <<<"$job" | sort -u)
# Every other `gh api` in the job is a write, or marked gh-read-exempt on the
# line above, so a new fail-closed read cannot skip the wait unnoticed.
stray="$(awk '/^      - name: / { helper = ($0 == "      - name: Write the rate-limit-aware read helper") }
  !helper && /gh api / && $0 !~ /^ *#/ && $0 !~ /gh api -X (POST|DELETE|PATCH|PUT) / && prev !~ /# gh-read-exempt: / { print }
  { prev = $0 }' <<<"$job")"
if [[ -z "$stray" ]]; then
  ok "every other gh api in ci-status is a write or marked gh-read-exempt"
else
  fail "ci-status reads through plain gh api without a gh-read-exempt mark: $stray"
fi

# The gh stub logs its arguments and answers each call with the next line of
# STUB_SCRIPT, as gh does with and without -i (the api-budget wrapper adds -i
# to every call it can):
#   ok <body>                       200 with 4000 of 5000 left
#   limit <remaining> <reset> <retry-after or -> <message>
#                                   403 with those headers and that message;
#                                   graphql's resource on a graphql call
#   last <reset> <body>             200 that spends the last request
#   fail <status> <message>         that status, no rate-limit headers
# Without -i only the body, or the error text on stderr, is printed. sleep
# logs its seconds, and date +%s answers STUB_NOW plus the seconds slept.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
n=$(wc -l <"$STUB_LOG")
read -r kind a b c rest <<<"$(sed -n "${n}p" <<<"$STUB_SCRIPT")"
include=; [[ "$2" == -i ]] && include=1
resource=core; [[ " $* " == *" graphql "* ]] && resource=graphql
case $kind in
ok)
  [[ -z $include ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: 4000\r\nX-Ratelimit-Resource: %s\r\n\r\n' "$resource"
  printf '%s\n' "$a${b:+ $b}${c:+ $c}${rest:+ $rest}"
  ;;
last)
  [[ -z $include ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: 0\r\nX-Ratelimit-Reset: %s\r\nX-Ratelimit-Resource: %s\r\n\r\n' "$a" "$resource"
  printf '%s\n' "$b"
  ;;
limit)
  if [[ -n $include ]]; then
    printf 'HTTP/2.0 403 Forbidden\r\nX-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: %s\r\nX-Ratelimit-Reset: %s\r\nX-Ratelimit-Resource: %s\r\n' "$a" "$b" "$resource"
    [[ $c == - ]] || printf 'Retry-After: %s\r\n' "$c"
    printf '\r\n{"message":"%s"}\n' "$rest"
  fi
  printf 'gh: %s (HTTP 403)\n' "$rest" >&2
  exit 1
  ;;
fail)
  [[ -z $include ]] || printf 'HTTP/2.0 %s X\r\n\r\n{"message":"%s"}\n' "$a" "$b${c:+ $c}${rest:+ $rest}"
  printf 'gh: %s (HTTP %s)\n' "$b${c:+ $c}${rest:+ $rest}" "$a" >&2
  exit 1
  ;;
*) echo "unscripted call $n" >&2; exit 1 ;;
esac
EOF
cat >"$TMP_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_SLEEPS"
EOF
cat >"$TMP_ROOT/bin/date" <<'EOF'
#!/usr/bin/env bash
echo $((STUB_NOW + $(awk '{ s += $1 } END { print s + 0 }' "$STUB_SLEEPS")))
EOF
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep" "$TMP_ROOT/bin/date"

NOW=1792800000
LIMITED="limit 0 $((NOW + 30)) - API rate limit exceeded for installation."

# run <commands>: sources gh-read.sh, then runs <commands>, in one bash -e
# step. The stops and deadline stay from earlier runs until fresh.
run() {
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/sleeps"
  out="$(PATH="$TMP_ROOT/bin:$PATH" RUNNER_TEMP="$TMP_ROOT" GITHUB_REPOSITORY=o/r STUB_LOG="$TMP_ROOT/log" STUB_SLEEPS="$TMP_ROOT/sleeps" \
    STUB_NOW="${STUB_NOW:-$NOW}" bash -ec ". \"\$RUNNER_TEMP/gh-read.sh\"; $1" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -c . "$TMP_ROOT/log")
  sleeps=$(paste -sd' ' "$TMP_ROOT/sleeps")
}
fresh() { ci_gh_read::reset "$TMP_ROOT" $((NOW + 600)); }
# check <label> <want-rc> <want-calls> <want-sleeps> [want-out] [refuse-out]
check() {
  if [[ "$rc" -ne "$2" ]]; then
    fail "$1: expected rc=$2 got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$3" ]]; then
    fail "$1: expected $3 call(s) got $calls: '$(cat "$TMP_ROOT/log")'"
  elif [[ "$sleeps" != "$4" ]]; then
    fail "$1: expected sleeps '$4' got '$sleeps'"
  elif [[ -n "${5:-}" && "$out" != *"$5"* ]]; then
    fail "$1: output lacks '$5': '$out'"
  elif [[ -n "${6:-}" && "$out" == *"$6"* ]]; then
    fail "$1: output has '$6': '$out'"
  else
    ok "$1"
  fi
}

fresh
STUB_SCRIPT='ok hello' run 'x=$(gh_read repos/o/r/pulls/1); echo "got $x"'
check "a read that succeeds prints its output once" 0 1 "" "got hello"
if [[ "$(cat "$TMP_ROOT/log")" == "api -i repos/o/r/pulls/1" ]]; then
  ok "gh_read passes its arguments to gh api through the wrapper and sends no probe"
else
  fail "gh_read called '$(cat "$TMP_ROOT/log")'"
fi

fresh
STUB_SCRIPT="last $((NOW + 3000)) spent" run 'x=$(gh_read repos/o/r/pulls/1); echo "got $x"'
check "a 200 that spends the last request returns its body and 0, with no wait" 0 1 "" "got spent" "waiting"
STUB_SCRIPT='ok never' run 'gh_read repos/o/r/pulls/2 || echo "rc=$?"'
check "the next read of that pool before its reset is refused without a call" 0 0 "" "rc=1"

fresh
STUB_SCRIPT="$LIMITED
ok after" run 'x=$(gh_read repos/o/r/pulls/1); echo "got $x"'
check "a primary rate limit waits until a second past the reset and reads again" 0 2 "31" "got after" "got API"
if [[ "$out" == *"::notice::'gh api repos/o/r/pulls/1' is rate limited (core); waiting 31s for the reset, then reading again."* ]]; then
  ok "the wait is announced on the step's stderr even inside a capture"
else
  fail "the wait notice is missing: '$out'"
fi
if ! grep -q 'rate_limit\|^api -i repos/o/r$' "$TMP_ROOT/log"; then
  ok "a rate-limited read sends no probe while limited"
else
  fail "a rate-limited read probed: '$(cat "$TMP_ROOT/log")'"
fi

fresh
STUB_SCRIPT="limit 10 $((NOW + 3000)) 7 You have exceeded a secondary rate limit.
ok after" run 'gh_read repos/o/r/pulls/1 >/dev/null'
check "a retry-after header sets the wait" 0 2 "8"

fresh
STUB_SCRIPT="limit 0 $((NOW + 50)) - API rate limit already exceeded for installation ID 1.
ok {}" run 'gh_read graphql -f query=x >/dev/null'
check "a graphql read waits for the graphql reset" 0 2 "51"

fresh
STUB_SCRIPT="limit 0 $((NOW + 3000)) - API rate limit already exceeded for installation ID 1.
ok core" run 'gh_read graphql -f query=x >/dev/null || true; gh_read repos/o/r/pulls/1; gh_read graphql -f query=x || echo "rc=$?"'
check "a graphql stop leaves core reads going and refuses graphql without a call" 0 2 "" "rc=1"

fresh
STUB_SCRIPT='limit 4999 0 - You have exceeded a secondary rate limit.
ok fine' run 'gh_read repos/o/r/pulls/1 >/dev/null || echo "rc=$?"'
check "a secondary rate limit with no retry-after, a guessed minute, fails the read without a wait" 0 1 "" "rc=1" "waiting"

fresh
STUB_SCRIPT="$LIMITED
ok never" run 'gh_read repos/o/r/pulls --paginate >/dev/null || echo "rc=$?"'
check "a paginated read whose headers are unseen fails at once on a primary limit, without a wait" 0 1 "" "rc=1" "waiting"
STUB_NOW=$((NOW + 120)) STUB_SCRIPT='ok never' run 'gh_read repos/o/r/pulls --paginate || echo "rc=$?"'
check "two minutes later that pool is still stopped and nothing is sent" 0 0 "" "rc=1"

fresh
STUB_SCRIPT="$LIMITED
ok never
ok never" run 'for attempt in 1 2 3; do gh_read repos/o/r/pulls --paginate >/dev/null && break; sleep 5; done; echo "attempts=$attempt"'
check "a caller's three-attempt loop sends the paginated read once" 0 1 "5 5 5" "attempts=3"

fresh
STUB_SCRIPT='fail 502 Bad Gateway' run 'api_budget_stop_until() { echo 12x; }; gh_read repos/o/r/pulls/1 || echo "rc=$?"'
check "a stop time that is not a number is not waited on" 0 0 "" "rc=1" "too great"

fresh
STUB_SCRIPT="$LIMITED
$LIMITED
ok never" run 'gh_read repos/o/r/pulls/1 || echo "rc=$?"'
check "a second rate limit after the wait fails the read without another wait" 0 2 "31" "rc=1"

fresh
STUB_SCRIPT="limit 0 $((NOW + 3000)) - API rate limit exceeded for installation." run 'gh_read repos/o/r/pulls/1 || echo "rc=$?"'
check "a reset past the deadline fails the read at once" 0 1 "" \
  "::error::GitHub's core API rate limit blocks 'gh api repos/o/r/pulls/1' until 2026-10-24T00:50:00Z, past the 2026-10-24T00:10:00Z ci-status can wait to inside its timeout; a re-run after 2026-10-24T00:50:00Z is needed."
STUB_SCRIPT='ok never' run 'gh_read repos/o/r/pulls/2 || echo "rc=$?"'
check "a later read of that pool, in a later step, before its reset fails without a call" 0 0 "" "was not sent: GitHub's core API rate limit holds until 2026-10-24T00:50:00Z"
STUB_SCRIPT='ok never' run 'gh pr view 2 || echo "rc=$?"'
check "any other gh call before that reset is refused too" 0 0 "" "rc=1"
STUB_SCRIPT='ok graphql' run 'gh_read graphql -f query=x'
check "a stop on core does not stop a graphql read" 0 1 "" "graphql"
STUB_NOW=$((NOW + 3001)) STUB_SCRIPT='ok again' run 'gh_read repos/o/r/pulls/2'
check "a read after that reset is sent" 0 1 "" "again"

fresh
STUB_SCRIPT="limit 0 $((NOW + 400)) - API rate limit exceeded for installation.
ok one" run 'gh_read repos/o/r/pulls/1 >/dev/null'
check "a 401 s wait inside the deadline is taken" 0 2 "401"
STUB_NOW=$((NOW + 560)) STUB_SCRIPT='limit 4999 0 61 You have exceeded a secondary rate limit.' \
  run 'gh_read repos/o/r/pulls/2 || echo "rc=$?"'
check "a later step's wait that would end past the deadline is not taken" 0 1 "" "past the 2026-10-24T00:10:00Z ci-status can wait to"

fresh
STUB_SCRIPT='fail 404 Not Found' run 'gh_read repos/o/r/contents/x 2>"$RUNNER_TEMP/err" || echo "rc=$?"; grep -c "HTTP 404" "$RUNNER_TEMP/err"'
check "any other error returns at once, its text on the caller's stderr" 0 1 "" $'rc=1\n1'

fresh
STUB_SCRIPT='fail 403 Resource not accessible by integration' run 'gh_read repos/o/r/pulls/1 || echo "rc=$?"'
check "a 403 that is not a rate limit returns at once" 0 1 "" "rc=1" "::error::"

test_harness::report
