#!/usr/bin/env bash
# test-scope: .github/actions/log-api-budget/api-budget.bash
# test-scope: .github/scripts/pr-merge/retry-call.bash
# test-scope: .github/scripts/pr-merge/rate-stop.bash
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-step.sh
. "$ROOT/scripts/lib/ci-step.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Resolve the queued pull request'
step="$(ci_step::read "$WORKFLOW" "$NAME" "$TMP_ROOT/body.sh")" || ci_step::abort "$WORKFLOW" "$NAME"

mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
if [[ -n ${STUB_LIMITED:-} && -f $STUB_LIMITED ]]; then
  reset=$(cat "$STUB_LIMITED")
  rm -f "$STUB_LIMITED"
  printf 'HTTP/2.0 403 Forbidden\r\nX-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: 0\r\nX-Ratelimit-Used: 5000\r\nX-Ratelimit-Reset: %s\r\nX-Ratelimit-Resource: core\r\n\r\n{"message":"API rate limit exceeded"}\n' "$reset"
  echo "gh: API rate limit exceeded (HTTP 403)" >&2
  exit 1
fi
if [[ " $* " == *" -i "* ]]; then
  printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: 4990\r\nX-Ratelimit-Used: 10\r\nX-Ratelimit-Reset: 1900000000\r\nX-Ratelimit-Resource: core\r\n\r\n'
fi
printf '%s\n' "$STUB_PR"
EOF
cat >"$TMP_ROOT/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$STUB_LOG"
EOF
cat >"$TMP_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$STUB_LOG"
exec /bin/sleep "$@"
EOF
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/git" "$TMP_ROOT/bin/sleep"

BASE=273c79b3a113ffd354cac686480c291ae0b96b76
HEAD=223dfbfe9c9ccba08e86650e28c9150b05c9959b
PR="{\"user\":{\"login\":\"dependabot[bot]\"},\"head\":{\"sha\":\"$HEAD\",\"ref\":\"dependabot/npm\",\"repo\":{\"full_name\":\"o/r\"}}}"
FORK="{\"user\":{\"login\":\"someone\"},\"head\":{\"sha\":\"$HEAD\",\"ref\":\"main\",\"repo\":{\"full_name\":\"someone/r\"}}}"

READING="200 5000 4990 10 1900000000 core repos/{repo}/pulls/{n}"

expect() {
  local label="$1" want_rc="$2" out rc got
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/output"
  rm -rf "$TMP_ROOT/runner"
  mkdir -p "$TMP_ROOT/runner"
  out="$(cd "$ROOT" && PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" QUEUE_HEAD_REF="$3" STUB_PR="$4" \
    RUNNER_TEMP="$TMP_ROOT/runner" GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$TMP_ROOT/output" \
    QUEUED_PR_WAIT_SECONDS=900 STUB_LIMITED="${LIMITED:-}" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  got="$(paste -sd' ' "$TMP_ROOT/output")"
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$5" != - && "$got" != "$5" ]]; then
    fail "$label: expected outputs '$5' got '$got'"
  elif [[ -n "${6:-}" ]] && ! grep -qxF -- "$6" "$TMP_ROOT/log"; then
    fail "$label: no call '$6' in '$(paste -sd'|' "$TMP_ROOT/log")'"
  elif [[ "$want_rc" -eq 0 && -z "${LIMITED:-}" && "$(cat "$TMP_ROOT/runner/api-budget/github-token" 2>/dev/null)" != "$READING" ]]; then
    fail "$label: expected the reading '$READING' got '$(cat "$TMP_ROOT/runner/api-budget/github-token" 2>/dev/null)'"
  else
    ok "$label"
  fi
}

expect "head commit comes from the pull request, not the ref's base sha" 0 \
  "gh-readonly-queue/main/pr-7492-$BASE" "$PR" \
  "author=dependabot[bot] head_ref=dependabot/npm head_sha=$HEAD waited=0" "git fetch --no-tags origin $HEAD"
expect "the pull request number is read from the ref" 0 \
  "gh-readonly-queue/main/pr-7492-$BASE" "$PR" - "api -i repos/o/r/pulls/7492"
expect "a fork's head branch is not passed" 0 \
  "gh-readonly-queue/main/pr-12-$BASE" "$FORK" "author=someone head_ref= head_sha=$HEAD waited=0"
expect "a non-queue ref fails" 1 "refs/heads/main" "$PR" ""
expect "a short sha in the ref fails" 1 "gh-readonly-queue/main/pr-7492-abc123" "$PR" ""

calls() { grep -cxF "api -i repos/o/r/pulls/7492" "$TMP_ROOT/log"; }
LIMITED="$TMP_ROOT/limited"
echo $(($(date +%s) + 1)) >"$LIMITED"
expect "a rate limit whose reset is inside the budget is waited out" 0 \
  "gh-readonly-queue/main/pr-7492-$BASE" "$PR" - "git fetch --no-tags origin $HEAD"
slept=$(sed -n 's/^sleep //p' "$TMP_ROOT/log" | awk '{ s += $1 } END { print s + 0 }')
want="author=dependabot[bot] head_ref=dependabot/npm head_sha=$HEAD waited=$slept"
if [[ "$(paste -sd' ' "$TMP_ROOT/output")" == "$want" ]]; then
  ok "the step outputs the successful read's fields and the seconds it waited"
else
  fail "expected outputs '$want' got '$(paste -sd' ' "$TMP_ROOT/output")'"
fi
if [[ $(calls) -eq 2 ]] && grep -q '^sleep ' "$TMP_ROOT/log"; then
  ok "the read is sent again after one wait"
else
  fail "expected two reads and a sleep, got '$(paste -sd'|' "$TMP_ROOT/log")'"
fi
echo $(($(date +%s) + 3600)) >"$LIMITED"
expect "a rate limit whose reset is past the budget fails" 1 \
  "gh-readonly-queue/main/pr-7492-$BASE" "$PR" ""
if [[ $(calls) -eq 1 ]] && ! grep -q '^sleep ' "$TMP_ROOT/log"; then
  ok "a reset past the budget sends one read and no wait"
else
  fail "expected one read and no sleep, got '$(paste -sd'|' "$TMP_ROOT/log")'"
fi
LIMITED=

test_harness::report
