#!/usr/bin/env bash
# Runs the `Write the rate-limit-aware read helper` step body of
# .github/workflows/pr-require-checks.yml's ci-status, then calls the gh_read
# function it writes, under bash -e, against stub `gh`, `sleep` and `date`.
#
# gh_read runs `gh api`. On a rate limit it waits once and reads again: until
# five seconds past the reset GET /rate_limit reports for the resource, 60 s
# for a secondary limit or an unreadable reset, one second when the window has
# already reset. A wait that would end past the deadline the step sets,
# RATE_LIMIT_WAIT_SECONDS after it runs, fails the read naming the reset and
# blocks that resource until it. Any other failure returns at once.
# test-scope: .github/workflows/pr-require-checks.yml
# test-scope: .github/workflows/pr-feedback-dispatch.yml
# shellcheck disable=SC2016 # the step snippets and the env expression are literal
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"
DISPATCH="$ROOT/.github/workflows/pr-feedback-dispatch.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

if ! RATE_LIMIT_WAIT_SECONDS=600 ci_gh_read::install "$WORKFLOW" "$TMP_ROOT"; then
  fail "no working 'Write the rate-limit-aware read helper' step in $WORKFLOW"
  test_harness::report
  exit 1
fi
if [[ "$(cat "$TMP_ROOT/gh-read.deadline")" -ge $(($(date +%s) + 590)) ]]; then
  ok "the step sets the wait deadline RATE_LIMIT_WAIT_SECONDS after it runs"
else
  fail "the step set the deadline '$(cat "$TMP_ROOT/gh-read.deadline")'"
fi

job="$(awk '/^  ci-status:$/ { on = 1 } on && /^  [a-z-]+:$/ && !/ci-status/ { exit } on { print }' "$WORKFLOW")"
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
cap="$(sed -nE 's/^      RATE_LIMIT_WAIT_SECONDS: ([0-9]+)$/\1/p' <<<"$job")"
timeout="$(sed -nE 's/^    timeout-minutes: ([0-9]+)$/\1/p' <<<"$job")"
if [[ -n "$cap" && -n "$timeout" && $((2 * cap / 60 + 5)) -le "$timeout" ]]; then
  ok "the job timeout ($timeout min) holds two ${cap}s wait windows plus the 5 min the other waits need"
else
  fail "the job timeout '$timeout' does not hold two '${cap}'s wait windows plus 5 minutes"
fi
if [[ "$(grep -c 'rate-limit-wait-seconds: \${{ env.RATE_LIMIT_WAIT_SECONDS }}' <<<"$job")" -eq 2 ]]; then
  ok "check-contract and aggregate-results wait under the same ceiling"
else
  fail "check-contract and aggregate-results do not both take rate-limit-wait-seconds from RATE_LIMIT_WAIT_SECONDS"
fi
poll="$(sed -nE "s/^          POLL_LIMIT_SECONDS: '([0-9]+)'$/\1/p" "$DISPATCH")"
if [[ -n "$poll" && -n "$timeout" && "$poll" -gt $((timeout * 60)) ]]; then
  ok "pr-feedback-dispatch polls an in-progress ci-status longer than its ${timeout} min timeout"
else
  fail "pr-feedback-dispatch's POLL_LIMIT_SECONDS '$poll' does not outlast ci-status's ${timeout} min timeout"
fi

# The stub logs its arguments. GET /rate_limit prints STUB_LIMIT_<resource>
# ("<remaining> <reset>") or fails when that is unset. Any other call takes the
# next line of STUB_SCRIPT: `ok <stdout>`, or `fail <stderr>`.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
if [[ "$2" == rate_limit ]]; then
  [[ "$4" == .resources.core* ]] && v=${STUB_LIMIT_core:-} || v=${STUB_LIMIT_graphql:-}
  [[ -n "$v" ]] || exit 1
  printf '%s\n' "$v"
  exit 0
fi
n=$(grep -vc '^api rate_limit ' "$STUB_LOG")
line=$(sed -n "${n}p" <<<"$STUB_SCRIPT")
case $line in
ok\ *) printf '%s\n' "${line#ok }" ;;
fail\ *) printf '%s\n' "${line#fail }" >&2; exit 1 ;;
*) echo "unscripted call $n" >&2; exit 1 ;;
esac
EOF
cat >"$TMP_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_SLEEPS"
EOF
cat >"$TMP_ROOT/bin/date" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$STUB_NOW"
EOF
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep" "$TMP_ROOT/bin/date"

LIMITED='fail gh: API rate limit exceeded for installation. (HTTP 403)'
NOW=1792800000

# run <commands>: sources gh-read.sh, then runs <commands>, in one bash -e
# step. The blocks and deadline stay from earlier runs until fresh.
run() {
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/sleeps"
  out="$(PATH="$TMP_ROOT/bin:$PATH" RUNNER_TEMP="$TMP_ROOT" STUB_LOG="$TMP_ROOT/log" STUB_SLEEPS="$TMP_ROOT/sleeps" \
    STUB_NOW="${STUB_NOW:-$NOW}" bash -ec ". \"\$RUNNER_TEMP/gh-read.sh\"; $1" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -vc '^api rate_limit ' "$TMP_ROOT/log")
  sleeps=$(paste -sd' ' "$TMP_ROOT/sleeps")
}
fresh() { ci_gh_read::reset "$TMP_ROOT" $((NOW + 600)); }
# check <label> <want-rc> <want-calls> <want-sleeps> [want-out] [refuse-out]
check() {
  if [[ "$rc" -ne "$2" ]]; then
    fail "$1: expected rc=$2 got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$3" ]]; then
    fail "$1: expected $3 read(s) got $calls: '$(cat "$TMP_ROOT/log")'"
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
if [[ "$(cat "$TMP_ROOT/log")" == "api repos/o/r/pulls/1" ]]; then
  ok "gh_read passes its arguments to gh api unchanged and reads no rate limit"
else
  fail "gh_read called '$(cat "$TMP_ROOT/log")'"
fi

fresh
STUB_LIMIT_core="0 $((NOW + 30))" STUB_SCRIPT="$LIMITED
ok after" run 'x=$(gh_read repos/o/r/pulls/1); echo "got $x"'
check "a primary rate limit waits until five seconds past the reset and reads again" 0 2 "35" "got after" "got API"
if [[ "$out" == *"::notice::'gh api repos/o/r/pulls/1' is rate limited (core); waiting 35s for the reset, then reading again."* ]]; then
  ok "the wait is announced on the step's stderr even inside a capture"
else
  fail "the wait notice is missing: '$out'"
fi

fresh
STUB_LIMIT_graphql="0 $((NOW + 50))" STUB_LIMIT_core="4999 $((NOW + 9))" STUB_SCRIPT='fail gh: GraphQL: API rate limit already exceeded for installation ID 1.
ok {}' run 'gh_read graphql -f query=x >/dev/null'
check "a graphql read waits for the graphql reset, not the core one" 0 2 "55"

fresh
STUB_LIMIT_core="4999 $((NOW + 9))" STUB_SCRIPT='fail gh: You have exceeded a secondary rate limit. (HTTP 403)
ok fine' run 'gh_read repos/o/r/pulls/1 >/dev/null'
check "a secondary rate limit waits 60 s" 0 2 "60"

fresh
STUB_SCRIPT="$LIMITED
ok fine" run 'gh_read repos/o/r/pulls/1 >/dev/null'
check "a rate limit whose reset is unreadable waits 60 s" 0 2 "60"

fresh
STUB_LIMIT_core="4999 $((NOW + 3000))" STUB_SCRIPT="$LIMITED
ok fine" run 'gh_read repos/o/r/pulls/1 >/dev/null'
check "a primary limit whose window has already reset reads again after a second" 0 2 "1"

fresh
STUB_LIMIT_core="0 $((NOW + 30))" STUB_SCRIPT='fail gh: Forbidden (HTTP 403)
ok fine' run 'gh_read repos/o/r/pulls/1 >/dev/null'
check "a 403 while the core limit is at 0 is a rate limit" 0 2 "35"

fresh
STUB_LIMIT_core="0 $((NOW + 30))" STUB_SCRIPT="$LIMITED
$LIMITED
ok never" run 'gh_read repos/o/r/pulls/1 || echo "rc=$?"'
check "a second rate limit after the wait fails the read without another wait" 0 2 "35" "rc=1"

fresh
STUB_LIMIT_core="0 $((NOW + 3000))" STUB_SCRIPT="$LIMITED" run 'gh_read repos/o/r/pulls/1 || echo "rc=$?"'
check "a reset past the deadline fails the read at once" 0 1 "" \
  "::error::GitHub's core API rate limit blocks 'gh api repos/o/r/pulls/1' until 2026-10-24T00:50:00Z, after ci-status stops waiting at 2026-10-24T00:10:00Z; re-run this run after 2026-10-24T00:50:00Z."
STUB_SCRIPT='ok never' run 'gh_read repos/o/r/pulls/2 || echo "rc=$?"'
check "a later read of that resource, in a later step, before its reset fails without a call" 0 0 "" "rc=1" "::error::"
STUB_SCRIPT='ok graphql' run 'gh_read graphql -f query=x'
check "a block on core does not stop a graphql read" 0 1 "" "graphql"
STUB_NOW=$((NOW + 3000)) STUB_SCRIPT='ok again' run 'gh_read repos/o/r/pulls/2'
check "a read after that reset is sent" 0 1 "" "again"

fresh
STUB_LIMIT_core="0 $((NOW + 400))" STUB_SCRIPT="$LIMITED
ok one" run 'gh_read repos/o/r/pulls/1 >/dev/null'
check "a 405 s wait inside the deadline is taken" 0 2 "405"
STUB_NOW=$((NOW + 560)) STUB_LIMIT_core="4999 $((NOW + 3600))" STUB_SCRIPT='fail gh: You have exceeded a secondary rate limit. (HTTP 403)' \
  run 'gh_read repos/o/r/pulls/2 || echo "rc=$?"'
check "a later step's wait that would end past the deadline is not taken" 0 1 "" "after ci-status stops waiting at 2026-10-24T00:10:00Z"

fresh
STUB_SCRIPT='fail gh: Not Found (HTTP 404)' run 'gh_read repos/o/r/contents/x 2>"$RUNNER_TEMP/err" || echo "rc=$?"; grep -c "HTTP 404" "$RUNNER_TEMP/err"'
check "any other error returns at once, its text on the caller's stderr" 0 1 "" $'rc=1\n1'
if grep -q '^api rate_limit ' "$TMP_ROOT/log"; then
  fail "a 404 read the rate limit"
else
  ok "a 404 reads no rate limit"
fi
fresh
STUB_LIMIT_core="4999 $((NOW + 30))" STUB_SCRIPT='fail gh: Resource not accessible by integration (HTTP 403)' run 'gh_read repos/o/r/pulls/1 || echo "rc=$?"'
check "a 403 that is not a rate limit returns at once" 0 1 "" "rc=1" "::error::"

test_harness::report
