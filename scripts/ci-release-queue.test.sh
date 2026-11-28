#!/usr/bin/env bash
# test-scope: .github/workflows/release-publish-plugins.yml .github/scripts/release-publish-plugins/ci-status.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/release-publish-plugins.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-step.sh
. "$ROOT/scripts/lib/ci-step.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Queue the checked head'
ci_step::read "$WORKFLOW" "$NAME" "$TMP_ROOT/body.sh" >/dev/null || ci_step::abort "$WORKFLOW" "$NAME"

for line in '    workflows: [PR Require Checks, PR Verify]' '    branches: [release/plugins, main]' \
  "      || github.event.workflow_run.path == '.github/workflows/pr-verify.yml' && github.event.workflow_run.actor.id == 337859524))" \
  "    && !(github.event.workflow_run.head_repository.full_name == github.repository" \
  "    || github.event.workflow_run.path == '.github/workflows/pr-verify.yml' && github.event.workflow_run.actor.id == 337859524))" \
  "  cancel-in-progress: \${{ github.event_name != 'push' && github.event_name != 'workflow_run' }}"; do
  if grep -qxF -- "$line" "$WORKFLOW"; then ok "the workflow carries '${line#"${line%%[! ]*}"}'"; else fail "the workflow lost '$line'"; fi
done

BIN="$TMP_ROOT/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
jq_expr=. prev=
for a in "$@"; do
  [ "$prev" = --jq ] && jq_expr=$a
  prev=$a
done
case "$*" in
*isInMergeQueue*) json='{"data":{"node":{"isInMergeQueue":false}}}' ;;
*check-runs*) json='{"check_runs":[{"started_at":"2026-11-28T12:00:00Z","status":"completed","conclusion":"success"}]}' ;;
*/statuses\?*) json=$FAKE_STATUSES ;;
*'mergeQueue(branch'*) json='{"data":{"repository":{"mergeQueue":{"id":"Q","entries":{"totalCount":0,"nodes":[]}}}}}' ;;
*enqueuePullRequest*) json='{"data":{"enqueuePullRequest":{"mergeQueueEntry":{"position":1}}}}' ;;
*) exit 9 ;;
esac
jq -r "$jq_expr" <<<"$json"
SH
cat >"$BIN/git" <<'SH'
#!/usr/bin/env bash
if [ "$1" = rev-parse ]; then echo 1111111111111111111111111111111111111111; fi
SH
chmod +x "$BIN/gh" "$BIN/git"

SHA=0123456789abcdef0123456789abcdef01234567
run() {
  : >"$TMP_ROOT/gh.log"
  LAST_OUTPUT="$(cd "$ROOT" && env -i PATH="$BIN:$PATH" HOME="$HOME" GH_LOG="$TMP_ROOT/gh.log" GITHUB_REPOSITORY=o/r GH_TOKEN=t \
    PR_ID=PR_7 PR_NUMBER=7 HEAD_SHA="$SHA" FAKE_STATUSES="$1" bash --noprofile --norc -e "$TMP_ROOT/body.sh" 2>&1)"
  LAST_STATUS=$?
  ENQUEUED="$(grep -c enqueuePullRequest "$TMP_ROOT/gh.log")"
}
status() { printf '[{"context":"pr-verify","state":"%s","creator":{"id":%s}}]' "$1" "${2:-41898282}"; }

for case in '[]|not posted' "$(status pending)|pending" "$(status success 12345)|not posted"; do
  run "${case%|*}"
  want="::notice::pr-verify on release pull request #7 is ${case#*|} at $SHA; a later run queues it."
  if [[ $LAST_STATUS -eq 0 && $ENQUEUED -eq 0 && "$LAST_OUTPUT" == *"$want"* ]]; then
    ok "pr-verify '${case%|*}' leaves the release unqueued with a notice"
  else
    fail "pr-verify '${case%|*}': status $LAST_STATUS, $ENQUEUED enqueues, output '$LAST_OUTPUT'"
  fi
done
for state in failure error; do
  run "$(status "$state")"
  want="::warning::pr-verify on release pull request #7 is $state at $SHA; fix or lift it, then a later run queues it."
  if [[ $LAST_STATUS -eq 0 && $ENQUEUED -eq 0 && "$LAST_OUTPUT" == *"$want"* ]]; then
    ok "pr-verify $state leaves the release unqueued with a warning"
  else
    fail "pr-verify $state: status $LAST_STATUS, $ENQUEUED enqueues, output '$LAST_OUTPUT'"
  fi
done
run "$(status success)"
if [[ $LAST_STATUS -eq 0 && $ENQUEUED -eq 1 && "$(grep enqueuePullRequest "$TMP_ROOT/gh.log")" == *"-f head=$SHA"* &&
  "$LAST_OUTPUT" == *"Queued release pull request #7 at $SHA."* ]]; then
  ok "pr-verify success from GitHub Actions queues the checked head"
else
  fail "pr-verify success: status $LAST_STATUS, $ENQUEUED enqueues, output '$LAST_OUTPUT'"
fi

test_harness::report
