#!/usr/bin/env bash
# Runs the `Resolve the queued pull request` step body of
# .github/workflows/pr-require-checks.yml under bash -e, against stub `gh` and
# `git`.
#
# The merge group's head ref is gh-readonly-queue/<base>/pr-<number>-<base sha>.
# The step must take the head commit from the pull request, never the ref's
# SHA: the Dependabot fragment exemption reads the commits up to that head.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Resolve the queued pull request'
step="$(awk -v name="      - name: $NAME" '$0 == name { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$step" >"$TMP_ROOT/body.sh"

if [[ ! -s "$TMP_ROOT/body.sh" ]]; then
  fail "no '$NAME' step with a run: | body in $WORKFLOW"
  test_harness::report
  exit 1
fi

# gh prints STUB_PR for any call; git logs its arguments.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
printf '%s\n' "$STUB_PR"
EOF
cat >"$TMP_ROOT/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$STUB_LOG"
EOF
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/git"

BASE=273c79b3a113ffd354cac686480c291ae0b96b76
HEAD=223dfbfe9c9ccba08e86650e28c9150b05c9959b
PR="{\"user\":{\"login\":\"dependabot[bot]\"},\"head\":{\"sha\":\"$HEAD\",\"ref\":\"dependabot/npm\",\"repo\":{\"full_name\":\"o/r\"}}}"
FORK="{\"user\":{\"login\":\"someone\"},\"head\":{\"sha\":\"$HEAD\",\"ref\":\"main\",\"repo\":{\"full_name\":\"someone/r\"}}}"

# expect <label> <want-rc> <QUEUE_HEAD_REF> <STUB_PR> <want-output|-> [want-log]
expect() {
  local label="$1" want_rc="$2" out rc got
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/output"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" QUEUE_HEAD_REF="$3" STUB_PR="$4" \
    GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$TMP_ROOT/output" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  got="$(paste -sd' ' "$TMP_ROOT/output")"
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$5" != - && "$got" != "$5" ]]; then
    fail "$label: expected outputs '$5' got '$got'"
  elif [[ -n "${6:-}" ]] && ! grep -qxF -- "$6" "$TMP_ROOT/log"; then
    fail "$label: no call '$6' in '$(paste -sd'|' "$TMP_ROOT/log")'"
  else
    ok "$label"
  fi
}

expect "head commit comes from the pull request, not the ref's base sha" 0 \
  "gh-readonly-queue/main/pr-7492-$BASE" "$PR" \
  "author=dependabot[bot] head_ref=dependabot/npm head_sha=$HEAD" "git fetch --no-tags origin $HEAD"
expect "the pull request number is read from the ref" 0 \
  "gh-readonly-queue/main/pr-7492-$BASE" "$PR" - "api repos/o/r/pulls/7492"
expect "a fork's head branch is not passed" 0 \
  "gh-readonly-queue/main/pr-12-$BASE" "$FORK" "author=someone head_ref= head_sha=$HEAD"
expect "a non-queue ref fails" 1 "refs/heads/main" "$PR" ""
expect "a short sha in the ref fails" 1 "gh-readonly-queue/main/pr-7492-abc123" "$PR" ""

test_harness::report
