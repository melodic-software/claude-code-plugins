#!/usr/bin/env bash
# Runs the `Fail a queued pull request labeled do-not-merge` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# A merge-group run carries no pull request, so this step is the only reader of
# the hold label in the merge queue (#5952). It must fail on the label, pass
# without it, and fail closed when it cannot tell.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Fail a queued pull request labeled do-not-merge'
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
if [[ "$step" == *"if: github.event_name == 'merge_group'"* ]]; then
  ok "step runs on merge_group only"
else
  fail "step lost its merge_group condition"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
# Inside ci-status, before the aggregate, so a red here is the job's answer.
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line hold_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi

# The stub logs its arguments; it fails the first STUB_FAILS calls, then
# prints STUB_LABELS one per line.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
calls=$(wc -l <"$STUB_LOG")
[[ "$calls" -gt "${STUB_FAILS:-0}" ]] || exit 1
[[ -z "$STUB_LABELS" ]] || tr ',' '\n' <<<"$STUB_LABELS"
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

SHA=0123456789abcdef0123456789abcdef01234567
QUEUE="refs/heads/gh-readonly-queue/main/pr-6419-$SHA"

# expect <label> <want-rc> <want-gh-calls> <want-pr|-> <GITHUB_REF> <STUB_LABELS> <STUB_FAILS> [want-out]
expect() {
  local label="$1" want_rc="$2" want_calls="$3" want_pr="$4" out rc calls
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REF="$5" STUB_LABELS="$6" STUB_FAILS="$7" \
    GITHUB_REPOSITORY=o/r bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(wc -l <"$TMP_ROOT/log")
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls gh call(s) got $calls"
  elif [[ "$want_pr" != - ]] &&
    [[ "$(sort -u "$TMP_ROOT/log")" != "api repos/o/r/issues/$want_pr/labels?per_page=100 --paginate --jq .[].name" ]]; then
    fail "$label: unexpected gh call '$(sort -u "$TMP_ROOT/log")'"
  elif [[ -n "${8:-}" && "$out" != *"$8"* ]]; then
    fail "$label: output lacks '$8': '$out'"
  else
    ok "$label"
  fi
}

expect "unlabeled queued pull request passes" 0 1 6419 "$QUEUE" "enhancement,ci" 0 "#6419 carries no"
expect "pull request with no labels passes" 0 1 6419 "$QUEUE" "" 0
expect "do-not-merge fails the run" 1 1 6419 "$QUEUE" "ci,do-not-merge" 0 "::error::#6419 carries the 'do-not-merge' label"
expect "a label that only contains the name does not hold" 0 1 6419 "$QUEUE" "do-not-merge-later,not-do-not-merge" 0
expect "ref without refs/heads/ is read" 1 1 6419 "gh-readonly-queue/main/pr-6419-$SHA" "do-not-merge" 0
expect "base branch with a slash is read" 1 1 12 "refs/heads/gh-readonly-queue/release/v2/pr-12-$SHA" "do-not-merge" 0
expect "a transient read failure is retried" 1 2 6419 "$QUEUE" "do-not-merge" 1
expect "an unreadable label list fails closed" 1 3 6419 "$QUEUE" "" 3 "::error::could not read the labels of #6419"
expect "a non-queue ref fails closed without a call" 1 0 - "refs/heads/main" "" 0 "::error::cannot read a pull request number"
expect "a short sha fails closed without a call" 1 0 - "refs/heads/gh-readonly-queue/main/pr-6419-abc123" "" 0

test_harness::report
