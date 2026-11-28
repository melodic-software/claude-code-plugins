#!/usr/bin/env bash
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-step.sh
. "$ROOT/scripts/lib/ci-step.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

GATE_NAME='Fail a lanes App pull request on kill switch, hold path, verifier or veto'
NAME='Report the verify gate as the pr-verify status on the group commit'
step="$(ci_step::read "$WORKFLOW" "$NAME" "$TMP_ROOT/body.sh")" || ci_step::abort "$WORKFLOW" "$NAME"
gate="$(ci_step::read "$WORKFLOW" "$GATE_NAME" "$TMP_ROOT/gate.sh")" || ci_step::abort "$WORKFLOW" "$GATE_NAME"

# shellcheck disable=SC2016 # workflow literals to match, not shell expansions
for line in "if: \${{ !cancelled() && github.event_name == 'merge_group' }}" \
  'continue-on-error: true' \
  'GROUP_SHA: ${{ github.sha }}' \
  'GATE: ${{ steps.lanes_hold.outcome }}'; do
  if [[ "$step" == *"$line"* ]]; then ok "step carries '$line'"; else fail "step lost '$line'"; fi
done
if [[ "$gate" == *"        id: lanes_hold"* ]]; then ok "the verify gate step carries the id the report reads"; else fail "the verify gate step lost id lanes_hold"; fi
report_count="$(grep -cE '^      - name: Report the verify gate as the pr-verify status on the group commit$' "$WORKFLOW")"
if [[ "$report_count" == 1 ]]; then ok "one report step"; else fail "expected one report step, found $report_count"; fi
order="$(grep -nE "^  ci-status:$|^      - name: ($GATE_NAME|$NAME|Check each skipped lane against scope)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line gate_line step_line next_line <<<"$order"
if [[ -n "${next_line:-}" && "$job_line" -lt "$gate_line" && "$gate_line" -lt "$step_line" && "$step_line" -lt "$next_line" ]]; then
  ok "step sits in ci-status right after the verify gate"
else
  fail "step is not inside ci-status after the verify gate (lines: $order)"
fi
job="$(awk '/^  ci-status:$/ { on = 1; next } on && /^  [a-z]/ { exit } on' "$WORKFLOW")"
if grep -qxF '      statuses: write' <<<"$job"; then ok "ci-status holds statuses: write"; else fail "ci-status lacks statuses: write"; fi

BIN="$TMP_ROOT/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
n=$(wc -l <"$GH_LOG")
[ "$n" -gt "${GH_FAILS:-0}" ]
SH
cat >"$BIN/sleep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$SLEEP_LOG"
SH
chmod +x "$BIN/gh" "$BIN/sleep"
: >"$TMP_ROOT/gh-read.sh"

SHA=0123456789abcdef0123456789abcdef01234567
run() {
  : >"$TMP_ROOT/gh.log"
  : >"$TMP_ROOT/sleep.log"
  LAST_OUTPUT="$(env -i PATH="$BIN:$PATH" HOME="$TMP_ROOT" RUNNER_TEMP="$TMP_ROOT" GH_LOG="$TMP_ROOT/gh.log" SLEEP_LOG="$TMP_ROOT/sleep.log" \
    GITHUB_REPOSITORY=o/r GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=9 GH_TOKEN=t GH_FAILS="${GH_FAILS:-0}" \
    GROUP_SHA="${GROUP_SHA-$SHA}" GATE="$1" bash --noprofile --norc -e "$TMP_ROOT/body.sh" 2>&1)"
  LAST_STATUS=$?
}
post() { printf 'api -X POST repos/o/r/statuses/%s -f state=%s -f context=pr-verify -f description=%s -f target_url=https://github.com/o/r/actions/runs/9' "$SHA" "$1" "$2"; }

run success
if [[ $LAST_STATUS -eq 0 && "$(cat "$TMP_ROOT/gh.log")" == "$(post success 'ci-status verify gate passed for the queued pull request')" ]]; then
  ok "a passing verify gate posts pr-verify success on the group commit"
else
  fail "a passing gate: status $LAST_STATUS, calls '$(cat "$TMP_ROOT/gh.log")'"
fi
for outcome in failure skipped cancelled ''; do
  run "$outcome"
  want="$(post failure "ci-status verify gate held the queued pull request (step ${outcome:-unknown})")"
  if [[ $LAST_STATUS -eq 0 && "$(cat "$TMP_ROOT/gh.log")" == "$want" ]]; then
    ok "a verify gate outcome of '${outcome:-empty}' posts pr-verify failure"
  else
    fail "gate outcome '$outcome': status $LAST_STATUS, calls '$(cat "$TMP_ROOT/gh.log")'"
  fi
done
GH_FAILS=2 run success
if [[ $LAST_STATUS -eq 0 && "$(wc -l <"$TMP_ROOT/gh.log")" -eq 3 && "$(paste -sd' ' "$TMP_ROOT/sleep.log")" == "5 10" ]]; then
  ok "a failed post is retried twice, 5s then 10s apart"
else
  fail "retry: status $LAST_STATUS, $(wc -l <"$TMP_ROOT/gh.log") calls, sleeps '$(paste -sd' ' "$TMP_ROOT/sleep.log")'"
fi
GH_FAILS=3 run success
if [[ $LAST_STATUS -ne 0 && "$(wc -l <"$TMP_ROOT/gh.log")" -eq 3 && "$LAST_OUTPUT" == *"::error::could not post pr-verify success on the merge-group commit $SHA"* ]]; then
  ok "three failed posts fail the step, which continues on error"
else
  fail "three failures: status $LAST_STATUS, output '$LAST_OUTPUT'"
fi
for bad_sha in '' main "${SHA}0" 'x; rm -rf /'; do
  GROUP_SHA="$bad_sha" run success
  if [[ $LAST_STATUS -ne 0 && ! -s "$TMP_ROOT/gh.log" && "$LAST_OUTPUT" == *"is not a commit SHA; no pr-verify status posted."* ]]; then
    ok "a group commit of '$bad_sha' posts nothing"
  else
    fail "group commit '$bad_sha': status $LAST_STATUS, calls '$(cat "$TMP_ROOT/gh.log")'"
  fi
done

test_harness::report
