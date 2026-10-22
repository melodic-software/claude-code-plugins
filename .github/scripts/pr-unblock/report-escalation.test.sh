#!/usr/bin/env bash
# Tests for report-escalation.sh with stub gh and git on PATH. The stub gh
# serves issue and comment JSON in the shape of the GitHub REST API (issue
# .labels[].name, comment .body and .user.type) and records every call.
# shellcheck disable=SC2016  # backticks and $STUB are literal text here
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/report-escalation.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HEAD_A=1111111111111111111111111111111111111111
HEAD_B=2222222222222222222222222222222222222222
MARKER='<!-- work-items:escalation lane=pr-unblock kind=escalated -->'
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}
has() {
  if grep -qF -- "$2" "$3"; then ok "$1"; else not_ok "$1: [$2] not in $3"; fi
}

mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
method=GET endpoint=''
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in
  -X) method=${args[i + 1]} ;;
  repos/*) endpoint=${args[i]} ;;
  body=@*)
    cat "${args[i]#body=@}" >>"$STUB/bodies"
    printf '\n=====\n' >>"$STUB/bodies"
    ;;
  esac
done
printf '%s %s\n' "$method" "$endpoint" >>"$STUB/requests"
case "$method $endpoint" in
"GET repos/o/r/issues/42") cat "$STUB/issue.json" ;;
"GET repos/o/r/issues/42/comments") cat "$STUB/comments.json" ;;
"POST repos/o/r/issues/42/labels")
  [[ -f $STUB/fail_labels ]] && { echo 'stub gh: label POST failed' >&2; exit 1; }
  echo '{}'
  ;;
"POST repos/o/r/issues/42/comments")
  # fail_comments holds how many more comment POSTs fail.
  left=$(cat "$STUB/fail_comments" 2>/dev/null || echo 0)
  if ((left > 0)); then
    echo $((left - 1)) >"$STUB/fail_comments"
    echo 'stub gh: comment POST failed' >&2
    exit 1
  fi
  echo '{}'
  ;;
"POST repos/o/r/statuses/"*)
  [[ -f $STUB/fail_status ]] && { echo 'stub gh: status POST failed' >&2; exit 1; }
  echo '{}'
  ;;
*) echo "stub gh: unexpected $method $endpoint" >&2; exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\necho git >>"$STUB/calls"\nexit 1\n' >"$TMP/bin/git"
printf '#!/usr/bin/env bash\necho "sleep $1" >>"$STUB/sleeps"\n' >"$TMP/bin/sleep"
chmod +x "$TMP/bin/gh" "$TMP/bin/git" "$TMP/bin/sleep"

# setup <labels-json-array> <comments-json-array> [tracker-json|none]
setup() {
  STUB="$(mktemp -d "$TMP/case.XXXXXX")"
  mkdir -p "$STUB/ws/.base"
  printf '{"number":42,"labels":%s}' "$1" >"$STUB/issue.json"
  printf '%s' "$2" >"$STUB/comments.json"
  : >"$STUB/calls"
  : >"$STUB/requests"
  : >"$STUB/bodies"
  if [[ ${3:-none} != none ]]; then
    printf '%s' "$3" >"$STUB/ws/.base/.work-item-tracker.json"
  fi
}
# run <reason> [head-sha]: runs from the workspace root, as the runner does.
# MODE, when set, is the script's argument; TARGET_URL passes through.
run() {
  set +e
  (cd "$STUB/ws" && env PATH="$TMP/bin:$PATH" STUB="$STUB" GH_TOKEN=t \
    GITHUB_REPOSITORY=o/r LANES_BOT_LOGIN="${LBL:-}" PR_NUMBER=42 HEAD_SHA="${2:-$HEAD_A}" \
    TARGET_URL="${TARGET_URL:-}" ESCALATION_REASON="$1" "$SUT" ${MODE:+"$MODE"}) >"$STUB/out" 2>&1
  RC=$?
  set -e
}
writes() { grep -c '^POST' "$STUB/requests" || true; }
comment() { printf '[{"body":%s,"user":{"login":"%s","type":"%s"}}]' "$(jq -Rs . <<<"$1")" "$2" "$3"; }
bot_marker() { comment "$MARKER"$'\n'"<!-- pr-unblock resume-key=$1 -->"$'\nbody' 'melodic-automation-lanes[bot]' Bot; }

# Rejected reasons: workflow-files is the retired name, the rest are not in the enum.
for reason in workflow-files bogus '' 'repeat-cap ' REPEAT-CAP; do
  setup '[]' '[]'
  run "$reason"
  check "rejects reason [$reason]: exit" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
  check "rejects reason [$reason]: no gh call" '' "$(cat "$STUB/calls")"
done

# Accepted reasons: one comment, one label, both on the PR.
for reason in protected-path-conflict workflow-staged unexpected-path-staged repeat-cap unresolved-conflict \
  feedback-protected-path feedback-round-cap feedback-uncertain feedback-not-landed feedback-invalid \
  feedback-partial feedback-incomplete feedback-disputed \
  dependency-round-cap dependency-invalid dependency-fix-not-landed dependency-security-close dependency-escalate \
  dependency-config-unreadable dependency-files-truncated dependency-control-uncited dependency-workflow-held dependency-fix-refused \
  ci-fix-round-cap ci-fix-empty ci-fix-invalid ci-fix-protected-path ci-fix-not-applied ci-fix-escalated; do
  setup '[]' '[]'
  run "$reason"
  check "$reason: exit 0" 0 "$RC"
  check "$reason: writes the label then a comment" \
    $'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments' \
    "$(grep '^POST' "$STUB/requests")"
  check "$reason: marker is the first line" "$MARKER" "$(head -n 1 "$STUB/bodies")"
  has "$reason: comment names the reason" "$reason" "$STUB/bodies"
  has "$reason: comment carries the resume key" "resume-key=$HEAD_A" "$STUB/bodies"
  has "$reason: comment says to remove the label" 'remove the `needs-human` label' "$STUB/bodies"
  has "$reason: comment says to dispatch pr-unblock" 'pr-unblock' "$STUB/bodies"
  has "$reason: comment names the PR to dispatch" 'pr-number=42' "$STUB/bodies"
  case $reason in
    feedback-*) want=address-feedback ;;
    dependency-*) want=review-dependency ;;
    ci-fix-*) want=fix-ci ;;
    *) want=resolve-conflicts ;;
  esac
  has "$reason: comment names the activity to dispatch" "-f pr-number=42 -f activity=$want" "$STUB/bodies"
  has "$reason: label defaults to needs-human" 'labels[]=needs-human' "$STUB/calls"
  check "$reason: the comment run posts no commit status" 0 "$(grep -c statuses "$STUB/requests" || true)"
done

ALL_REASONS=(protected-path-conflict workflow-staged unexpected-path-staged repeat-cap unresolved-conflict
  feedback-protected-path feedback-round-cap feedback-uncertain feedback-not-landed feedback-invalid
  feedback-partial feedback-incomplete feedback-disputed
  dependency-round-cap dependency-invalid dependency-fix-not-landed dependency-security-close dependency-escalate
  dependency-config-unreadable dependency-files-truncated dependency-control-uncited dependency-workflow-held dependency-fix-refused
  ci-fix-round-cap ci-fix-empty ci-fix-invalid ci-fix-protected-path ci-fix-not-applied ci-fix-escalated)

# Status mode: a failing pr-unblock/conflict status on the head, only for unresolved-conflict.
setup '[]' '[]'
MODE=status TARGET_URL=https://example.test/run/1 run unresolved-conflict
check "status, unresolved-conflict: exit 0" 0 "$RC"
check "status, unresolved-conflict: one status POST on the head, nothing else" \
  "POST repos/o/r/statuses/$HEAD_A" "$(cat "$STUB/requests")"
has "status, unresolved-conflict: state failure" 'state=failure' "$STUB/calls"
has "status, unresolved-conflict: context names the conflict" 'context=pr-unblock/conflict' "$STUB/calls"
has "status, unresolved-conflict: description says CI does not run" \
  'description=Conflicts with the base branch; CI does not run until they are resolved' "$STUB/calls"
has "status, unresolved-conflict: links the run" 'target_url=https://example.test/run/1' "$STUB/calls"

setup '[]' '[]'
MODE=status run unresolved-conflict "$HEAD_B"
check "status on another head: posted on that head" "POST repos/o/r/statuses/$HEAD_B" "$(cat "$STUB/requests")"
check "status without TARGET_URL: no target_url" 0 "$(grep -c target_url "$STUB/calls" || true)"

for reason in "${ALL_REASONS[@]}"; do
  [[ $reason == unresolved-conflict ]] && continue
  setup '[]' '[]'
  MODE=status run "$reason"
  check "status, $reason: exit 0" 0 "$RC"
  check "status, $reason: no gh call" '' "$(cat "$STUB/calls")"
done

setup '[]' '[]'
touch "$STUB/fail_status"
MODE=status run unresolved-conflict
check "status POST fails: exit 1" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"

setup '[]' '[]'
MODE=status run unresolved-conflict not-a-sha
check "status, malformed head sha: exit 1" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "status, malformed head sha: no gh call" '' "$(cat "$STUB/calls")"

setup '[]' '[]'
MODE=bogus run unresolved-conflict
check "unknown mode: exit 1" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "unknown mode: no gh call" '' "$(cat "$STUB/calls")"

# The role label resolves from the base tracker config, not from the workspace root.
setup '[]' '[]' '{"config":{"role_labels":{"human-gated":"status: blocked-human"}}}'
printf '{"config":{"role_labels":{"human-gated":"from-head"}}}' >"$STUB/ws/.work-item-tracker.json"
run repeat-cap
check "role label: exit 0" 0 "$RC"
has "role label: label from config" 'labels[]=status: blocked-human' "$STUB/calls"
has "role label: comment names it" 'remove the `status: blocked-human` label' "$STUB/bodies"
check "role label: workspace-root config ignored" 0 "$(grep -c from-head "$STUB/calls" || true)"

setup '[]' '[]' '{"config":{"role_labels":{"autonomous-eligible":"go"}}}'
run repeat-cap
has "role label: absent role defaults to needs-human" 'labels[]=needs-human' "$STUB/calls"

setup '[]' '[]' '{not json'
run repeat-cap
check "role label: unparsable config fails" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "role label: unparsable config writes nothing" 0 "$(writes)"

for entry in false null 7 '""' '["needs-human"]'; do
  setup '[]' '[]' "{\"config\":{\"role_labels\":{\"human-gated\":$entry}}}"
  run repeat-cap
  check "role label: present entry $entry fails" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
  check "role label: present entry $entry makes no gh call" '' "$(cat "$STUB/calls")"
done

# Idempotency.
setup '[{"name":"needs-human"}]' "$(bot_marker "$HEAD_A")"
run unresolved-conflict
check "re-run on the same head: exit 0" 0 "$RC"
check "re-run on the same head: no write" 0 "$(writes)"

setup '[{"name":"needs-human"}]' "$(bot_marker "$HEAD_B")"
run unresolved-conflict
check "labeled, marker for another head: comment only" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

setup '[]' "$(bot_marker "$HEAD_A")"
run unresolved-conflict
check "label removed by a human, same head: escalates again" \
  $'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

# Partial failure: a failed label write posts no comment; a failed comment
# write is retried; a retry run after the label landed posts exactly one comment.
LABEL_THEN_3_COMMENTS=$'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments\nPOST repos/o/r/issues/42/comments\nPOST repos/o/r/issues/42/comments'
setup '[]' '[]'
touch "$STUB/fail_labels"
run unresolved-conflict
check "label write fails: exit 1" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "label write fails: no comment posted" 0 "$(grep -c '^POST repos/o/r/issues/42/comments$' "$STUB/requests" || true)"

setup '[]' '[]'
echo 1 >"$STUB/fail_comments"
run unresolved-conflict
check "comment write fails once: exit 0" 0 "$RC"
check "comment write fails once: label, then the comment twice" \
  $'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments\nPOST repos/o/r/issues/42/comments' \
  "$(grep '^POST' "$STUB/requests")"
check "comment write fails once: backs off once" 'sleep 5' "$(cat "$STUB/sleeps" 2>/dev/null)"

# exhausted <name>: a run whose comment write fails every attempt (the job
# fails, the label is on), then the PR as the next run sees it: label on,
# comment write working, request log cleared.
exhausted() {
  setup '[]' '[]'
  echo 99 >"$STUB/fail_comments"
  run unresolved-conflict
  check "$1: comment write fails every attempt: exit 1" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
  check "$1: comment write fails every attempt: label on, three comment attempts" \
    "$LABEL_THEN_3_COMMENTS" "$(grep '^POST' "$STUB/requests")"
  printf '{"number":42,"labels":[{"name":"needs-human"}]}' >"$STUB/issue.json"
  echo 0 >"$STUB/fail_comments"
  : >"$STUB/requests"
  : >"$STUB/bodies"
}

exhausted "retry after a failed comment"
run unresolved-conflict
check "retry after a failed comment: exit 0" 0 "$RC"
check "retry after a failed comment: one comment, no label" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

# A label left by a failed comment write is explained by the next run, on a later head too.
exhausted "label left, later head"
run unresolved-conflict "$HEAD_B"
check "label left, later head: exit 0" 0 "$RC"
check "label left, later head: explains the label" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"
has "label left, later head: comment carries the later resume key" "resume-key=$HEAD_B" "$STUB/bodies"

setup '[{"name":"needs-human"}]' "$(comment "$MARKER"$'\n'"<!-- pr-unblock resume-key=$HEAD_A -->" someone User)"
run unresolved-conflict
check "marker written by a user does not count" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

setup '[{"name":"needs-human"}]' "$(comment "$MARKER"$'\n'"<!-- pr-unblock resume-key=$HEAD_A -->" 'other-app[bot]' Bot)"
run unresolved-conflict
check "marker written by another bot does not count" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

setup '[{"name":"needs-human"}]' "$(comment "$MARKER"$'\n'"<!-- pr-unblock resume-key=$HEAD_A -->" 'other-app[bot]' Bot)"
LBL='other-app[bot]' run unresolved-conflict
check "LANES_BOT_LOGIN names the lanes identity: no write" 0 "$(writes)"

# Input validation.
setup '[]' '[]'
run repeat-cap not-a-sha
check "rejects a malformed head sha" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "malformed head sha: no gh call" '' "$(cat "$STUB/calls")"

# Never touches the branch: no git, no contents API, no write outside the PR's issue.
setup '[]' '[]'
run workflow-staged
check "never runs git" 0 "$(grep -c '^git' "$STUB/calls" || true)"
check "never calls the contents API" 0 "$(grep -c 'contents/' "$STUB/calls" || true)"
check "writes only the issue comments and labels" 0 \
  "$(grep -vE '^(GET|POST) repos/o/r/issues/42(/comments|/labels)?$' "$STUB/requests" | grep -c . || true)"

exit "$FAILED"
