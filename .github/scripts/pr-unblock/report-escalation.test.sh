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
  repos/* | graphql) endpoint=${args[i]} ;;
  body=@*)
    cat "${args[i]#body=@}" >>"$STUB/bodies"
    printf '\n=====\n' >>"$STUB/bodies"
    ;;
  esac
done
printf '%s %s\n' "$method" "$endpoint" >>"$STUB/requests"
case "$method $endpoint" in
"GET repos/o/r/issues/42") cat "$STUB/issue.json" ;;
"GET repos/o/r/issues/42/comments?per_page=100") cat "$STUB/comments.json" ;;
"GET graphql")
  [[ -f $STUB/fail_graphql ]] && { echo 'stub gh: graphql failed' >&2; exit 1; }
  # threads.json holds an array of pages; each graphql call serves the next.
  n=$(cat "$STUB/graphql_n" 2>/dev/null || echo 0)
  echo $((n + 1)) >"$STUB/graphql_n"
  if [[ -f $STUB/threads.json ]]; then
    jq -e ".[$n]" "$STUB/threads.json" || { echo "stub gh: no page $n" >&2; exit 1; }
  else
    echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}'
  fi
  ;;
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
"PATCH repos/o/r/issues/comments/"*)
  echo '{}'
  ;;
"GET repos/o/r/commits/"*"/statuses?per_page=100")
  if [[ -f $STUB/fail_statuses ]]; then
    echo '{"message":"API rate limit exceeded","status":"403"}'
    printf 'gh: API rate limit exceeded (HTTP 403)\n100%% used\n' >&2
    exit 1
  fi
  cat "$STUB/statuses.json" 2>/dev/null || echo '[]'
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
writes() { grep -cE '^(POST|PATCH)' "$STUB/requests" || true; }
# comment <body> <login> <type> [id]
comment() { printf '[{"id":%s,"body":%s,"user":{"login":"%s","type":"%s"}}]' "${4:-1}" "$(jq -Rs . <<<"$1")" "$2" "$3"; }
# bot_marker <head> [reason]: the lanes App's escalation comment for that head and reason.
bot_marker() { comment "$MARKER"$'\n'"<!-- pr-unblock resume-key=$1 -->"$'\nbody\n\n- Reason: `'"${2:-feedback-question-design}"'`' 'melodic-automation-lanes[bot]' Bot; }
activity_of() {
  case $1 in
    feedback-*) echo address-feedback ;;
    dependency-*) echo review-dependency ;;
    ci-fix-*) echo fix-ci ;;
    shared-copy-*) echo sync-shared-copies ;;
    *) echo resolve-conflicts ;;
  esac
}
context_of() {
  local activity
  activity=$(activity_of "$1")
  if [[ $activity == resolve-conflicts ]]; then echo pr-unblock/conflict; else echo "pr-unblock/$activity"; fi
}

# The routes: a person only for the owner's three reasons (an intent or
# design question, a CRITICAL security risk or a billing risk, a person's own
# thread or hold) and a severity the lane cannot read. feedback-uncertain and
# feedback-disputed are the findings no adjudicator judges: CRITICAL, a
# security-review finding rated CRITICAL or unrated, one of no known
# lane, or a person's own thread. feedback-round-cap is a person's hold or a
# thread only a person decides. dependency-fix-refused is a commit of untrusted
# provenance, a trust hold the owner keeps. Every other stop is a failing
# status, and SESSION_REASONS, a change the lane cannot make (a protected
# path, a weakened required check after its fresh fixer round, a check the
# rung-up retry could not fix, a dependency update the review could not
# finish), also put the PR in the session-builder
# queue with needs-session instead of in front of a person.
HOLD_REASONS=(feedback-round-cap feedback-uncertain feedback-disputed
  feedback-question-intent feedback-question-design feedback-question-security
  dependency-security-close dependency-escalate dependency-fix-refused)
SESSION_REASONS=(protected-path-conflict conflict-patch-protected-path
  feedback-protected-path ci-fix-protected-path ci-fix-weaken-required ci-fix-escalated
  dependency-round-cap dependency-fix-not-landed dependency-config-unreadable
  dependency-files-truncated dependency-control-uncited dependency-workflow-unpinned
  shared-copy-tooling-changed shared-copy-path-unregistered shared-copy-unexpected-path-staged
  shared-copy-patch-protected-path)
FAIL_REASONS=(workflow-staged unexpected-path-staged repeat-cap unresolved-conflict conflict-patch-invalid conflict-patch-not-applied
  feedback-not-converging feedback-verifier-open feedback-not-landed feedback-invalid feedback-partial
  feedback-incomplete feedback-stood-open feedback-unadjudicated feedback-untaken-threads feedback-publish-failed
  dependency-invalid
  ci-fix-round-cap ci-fix-empty ci-fix-invalid ci-fix-not-applied ci-fix-weaken-retry
  shared-copy-workflow-staged shared-copy-patch-invalid shared-copy-patch-not-applied)
ROUTES="$SCRIPT_DIR/escalation-routes.json"
check "the routing table holds exactly these reasons" \
  "$(printf '%s\n' "${HOLD_REASONS[@]}" "${SESSION_REASONS[@]}" "${FAIL_REASONS[@]}" | sort)" "$(jq -r 'keys[]' "$ROUTES" | sort)"
check "the routing table holds these for a person" \
  "$(printf '%s\n' "${HOLD_REASONS[@]}" | sort)" "$(jq -r 'to_entries[] | select(.value.route == "hold") | .key' "$ROUTES" | sort)"
check "the routing table queues these for a session builder, each a fail route" \
  "$(printf '%s\n' "${SESSION_REASONS[@]}" | sort)" "$(jq -r 'to_entries[] | select(.value.route == "fail" and .value.label == "needs-session") | .key' "$ROUTES" | sort)"
check "the routing table names no other label" "" "$(jq -r 'to_entries[] | select(.value | has("label")) | select(.value.route != "fail" or .value.label != "needs-session") | .key' "$ROUTES")"
for reason in "${HOLD_REASONS[@]}" "${SESSION_REASONS[@]}" "${FAIL_REASONS[@]}"; do
  check "$reason: the table's activity" "$(activity_of "$reason")" "$(jq -r --arg r "$reason" '.[$r].activity' "$ROUTES")"
done

# Rejected reasons: not a reason name at all.
for reason in '' 'repeat-cap ' REPEAT-CAP 'bogus;x'; do
  setup '[]' '[]'
  run "$reason"
  check "rejects reason [$reason]: exit" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
  check "rejects reason [$reason]: no gh call" '' "$(cat "$STUB/calls")"
done

# Fail-safe: a well-formed reason the table does not list (a retired name
# included) holds for a person, with no activity to dispatch, and posts no
# commit status.
for reason in bogus workflow-files dependency-workflow-held; do
  setup '[]' '[]'
  run "$reason"
  check "$reason, unknown: exit 0" 0 "$RC"
  check "$reason, unknown: writes the label then a comment" \
    $'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"
  has "$reason, unknown: label is needs-human" 'labels[]=needs-human' "$STUB/calls"
  check "$reason, unknown: marker is the first line" "$MARKER" "$(head -n 1 "$STUB/bodies")"
  has "$reason, unknown: comment names the reason" "- Reason: \`$reason\`" "$STUB/bodies"
  has "$reason, unknown: comment says the table does not list it" 'its routing table does not list' "$STUB/bodies"
  check "$reason, unknown: no activity to dispatch" 0 "$(grep -c 'activity=' "$STUB/bodies" || true)"
  setup '[]' '[]'
  MODE=status run "$reason"
  check "$reason, unknown, status mode: exit 0" 0 "$RC"
  check "$reason, unknown, status mode: no write" 0 "$(writes)"
done

# Session-builder reasons: the needs-session label, then one lane-stopped
# comment that names it; never the human-gated label.
for reason in "${SESSION_REASONS[@]}"; do
  setup '[]' '[]'
  run "$reason"
  want=$(activity_of "$reason")
  check "$reason, session: exit 0" 0 "$RC"
  check "$reason, session: the needs-session label, then one comment" \
    $'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"
  has "$reason, session: label is needs-session" 'labels[]=needs-session' "$STUB/calls"
  check "$reason, session: never needs-human" 0 "$(grep -c 'needs-human' "$STUB/bodies" "$STUB/calls" | awk -F: '{s+=$2} END {print s}')"
  check "$reason, session: marker is the first line" "<!-- pr-unblock:lane-stopped activity=$want -->" "$(head -n 1 "$STUB/bodies")"
  has "$reason, session: comment names the queue" 'labels it `needs-session` for a session builder' "$STUB/bodies"
  has "$reason, session: names the failing status" "failing \`$(context_of "$reason")\` status" "$STUB/bodies"
  has "$reason, session: gives the dispatch" "-f pr-number=42 -f activity=$want" "$STUB/bodies"
  setup '[]' '[]'
  MODE=status run "$reason"
  check "$reason, session, status mode: posts the failing status" "POST repos/o/r/statuses/$HEAD_A" "$(grep '^POST' "$STUB/requests")"
done

# With needs-session already on, the comment goes up and the label is not written again.
setup '[{"name":"needs-session"}]' '[]'
run ci-fix-weaken-required
check "session, already labeled: comment only" 'POST repos/o/r/issues/42/comments' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"

# Held reasons: one comment, one label, both on the PR.
for reason in "${HOLD_REASONS[@]}"; do
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
  want=$(activity_of "$reason")
  has "$reason: comment names the activity to dispatch" "-f pr-number=42 -f activity=$want" "$STUB/bodies"
  has "$reason: label defaults to needs-human" 'labels[]=needs-human' "$STUB/calls"
  check "$reason: the comment run posts no commit status" 0 "$(grep -c statuses "$STUB/requests" || true)"
done

# Fail-routed reasons: one lanes-stopped comment, no label, no status from
# the comment run.
for reason in "${FAIL_REASONS[@]}"; do
  setup '[]' '[]'
  run "$reason"
  want=$(activity_of "$reason")
  check "$reason, fail: exit 0" 0 "$RC"
  check "$reason, fail: one comment, no label" 'POST repos/o/r/issues/42/comments' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"
  check "$reason, fail: marker is the first line" "<!-- pr-unblock:lane-stopped activity=$want -->" "$(head -n 1 "$STUB/bodies")"
  check "$reason, fail: no escalation marker" 0 "$(grep -c 'work-items:escalation' "$STUB/bodies" || true)"
  has "$reason, fail: names the reason" "- Reason: \`$reason\`" "$STUB/bodies"
  has "$reason, fail: names the head" "- Head: \`$HEAD_A\`" "$STUB/bodies"
  has "$reason, fail: names the failing status" "failing \`$(context_of "$reason")\` status" "$STUB/bodies"
  has "$reason, fail: says a retry or a new head runs again" 'A new commit to the branch starts clean' "$STUB/bodies"
  has "$reason, fail: gives the dispatch" "-f pr-number=42 -f activity=$want" "$STUB/bodies"
  check "$reason, fail: names no label" 0 "$(grep -c 'needs-human' "$STUB/bodies" "$STUB/calls" | awk -F: '{s+=$2} END {print s}')"
  check "$reason, fail: reads no issue labels" 0 "$(grep -c '^GET repos/o/r/issues/42$' "$STUB/requests" || true)"
  check "$reason, fail: no commit status" 0 "$(grep -c statuses "$STUB/requests" || true)"
done

# Session-builder reasons: the needs-session label, then one lane-stopped
# comment that names it; never the human-gated label.
for reason in "${SESSION_REASONS[@]}"; do
  setup '[]' '[]'
  run "$reason"
  want=$(activity_of "$reason")
  check "$reason, session: exit 0" 0 "$RC"
  check "$reason, session: the needs-session label, then one comment" \
    $'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"
  has "$reason, session: label is needs-session" 'labels[]=needs-session' "$STUB/calls"
  check "$reason, session: never needs-human" 0 "$(grep -c 'needs-human' "$STUB/bodies" "$STUB/calls" | awk -F: '{s+=$2} END {print s}')"
  check "$reason, session: marker is the first line" "<!-- pr-unblock:lane-stopped activity=$want -->" "$(head -n 1 "$STUB/bodies")"
  has "$reason, session: comment names the queue" 'labels it `needs-session` for a session builder' "$STUB/bodies"
  has "$reason, session: names the failing status" "failing \`$(context_of "$reason")\` status" "$STUB/bodies"
  has "$reason, session: gives the dispatch" "-f pr-number=42 -f activity=$want" "$STUB/bodies"
  setup '[]' '[]'
  MODE=status run "$reason"
  check "$reason, session, status mode: posts the failing status" "POST repos/o/r/statuses/$HEAD_A" "$(grep '^POST' "$STUB/requests")"
done

# With needs-session already on, the comment goes up and the label is not written again.
setup '[{"name":"needs-session"}]' '[]'
run ci-fix-escalated
check "session, already labeled: comment only" 'POST repos/o/r/issues/42/comments' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"

# A session removed needs-session without a new head, and the lane stops
# again with the same comment: the label goes back on, the comment is untouched.
setup '[]' '[]'
run ci-fix-escalated
session_body=$(sed '/^=====$/d' "$STUB/bodies")
setup '[]' "$(comment "$session_body" 'melodic-automation-lanes[bot]' Bot 77)"
run ci-fix-escalated
check "session, same head, label removed: exit 0" 0 "$RC"
check "session, same head, label removed: label only" 'POST repos/o/r/issues/42/labels' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"
setup '[{"name":"needs-session"}]' "$(comment "$session_body" 'melodic-automation-lanes[bot]' Bot 77)"
run ci-fix-escalated
check "session, same head, still labeled: no write" 0 "$(writes)"

# The fail comment is one per activity, edited in place: unchanged, nothing
# is written; on a new head it is edited, never posted again.
STOP_MARKER='<!-- pr-unblock:lane-stopped activity=fix-ci -->'
setup '[]' '[]'
run ci-fix-round-cap
fail_body=$(sed '/^=====$/d' "$STUB/bodies")
setup '[]' "$(comment "$fail_body" 'melodic-automation-lanes[bot]' Bot 77)"
run ci-fix-round-cap
check "fail, same head, comment unchanged: exit 0" 0 "$RC"
check "fail, same head, comment unchanged: no write" 0 "$(writes)"

# A session removed needs-session without a new head, and the lane stops
# again with the same comment: the label goes back on, the comment is untouched.
setup '[]' '[]'
run ci-fix-weaken-required
session_body=$(sed '/^=====$/d' "$STUB/bodies")
setup '[]' "$(comment "$session_body" 'melodic-automation-lanes[bot]' Bot 77)"
run ci-fix-weaken-required
check "session, same head, label removed: exit 0" 0 "$RC"
check "session, same head, label removed: label only" 'POST repos/o/r/issues/42/labels' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"
setup '[{"name":"needs-session"}]' "$(comment "$session_body" 'melodic-automation-lanes[bot]' Bot 77)"
run ci-fix-weaken-required
check "session, same head, still labeled: no write" 0 "$(writes)"

setup '[]' "$(comment "$STOP_MARKER"$'\nolder text' 'melodic-automation-lanes[bot]' Bot 77)"
run ci-fix-round-cap "$HEAD_B"
check "fail, new head: edits the comment in place" 'PATCH repos/o/r/issues/comments/77' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"
has "fail, new head: the edit names the new head" "- Head: \`$HEAD_B\`" "$STUB/bodies"

setup '[]' "$(comment "$STOP_MARKER"$'\nolder text' someone User 77)"
run ci-fix-round-cap
check "fail: a marker a user wrote is not the lane's comment" 'POST repos/o/r/issues/42/comments' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"

setup '[]' "$(comment '<!-- pr-unblock:lane-stopped activity=address-feedback -->'$'\nolder' 'melodic-automation-lanes[bot]' Bot 77)"
run ci-fix-round-cap
check "fail: another activity's comment is left alone" 'POST repos/o/r/issues/42/comments' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"

# A held reason on a PR that already shows a fail comment still holds.
setup '[]' "$(comment "$STOP_MARKER"$'\nolder text' 'melodic-automation-lanes[bot]' Bot 77)"
run feedback-question-security
check "hold beside a fail comment: label then a new comment" \
  $'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments' "$(grep -E '^(POST|PATCH)' "$STUB/requests")"

# Status mode: a failing commit status on the head for a fail-routed reason,
# pr-unblock/conflict for resolve-conflicts, pr-unblock/<activity> otherwise.
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

# Re-armed on a new head: the status is the head's, so a later head starts
# with none and gets its own only if the lane stops there too.
setup '[]' '[]'
MODE=status run unresolved-conflict "$HEAD_B"
check "status on another head: posted on that head" "POST repos/o/r/statuses/$HEAD_B" "$(cat "$STUB/requests")"
check "status without TARGET_URL: no target_url" 0 "$(grep -c target_url "$STUB/calls" || true)"

for reason in "${FAIL_REASONS[@]}"; do
  [[ $reason == unresolved-conflict ]] && continue
  setup '[]' '[]'
  MODE=status run "$reason"
  check "status, $reason: exit 0" 0 "$RC"
  check "status, $reason: one status POST on the head" "POST repos/o/r/statuses/$HEAD_A" "$(cat "$STUB/requests")"
  has "status, $reason: state failure" 'state=failure' "$STUB/calls"
  has "status, $reason: context" "context=$(context_of "$reason")" "$STUB/calls"
  has "status, $reason: description names the reason" "description=Lane stopped: $reason; checked again on a new head" "$STUB/calls"
done

for reason in "${HOLD_REASONS[@]}"; do
  setup '[]' '[]'
  MODE=status run "$reason"
  check "status, held $reason: exit 0" 0 "$RC"
  check "status, held $reason: no gh call" '' "$(cat "$STUB/calls")"
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
run feedback-question-design
check "role label: exit 0" 0 "$RC"
has "role label: label from config" 'labels[]=status: blocked-human' "$STUB/calls"
has "role label: comment names it" 'remove the `status: blocked-human` label' "$STUB/bodies"
check "role label: workspace-root config ignored" 0 "$(grep -c from-head "$STUB/calls" || true)"

setup '[]' '[]' '{"config":{"role_labels":{"autonomous-eligible":"go"}}}'
run feedback-question-design
has "role label: absent role defaults to needs-human" 'labels[]=needs-human' "$STUB/calls"

setup '[]' '[]' '{not json'
run feedback-question-design
check "role label: unparsable config fails" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "role label: unparsable config writes nothing" 0 "$(writes)"

for entry in false null 7 '""' '["needs-human"]'; do
  setup '[]' '[]' "{\"config\":{\"role_labels\":{\"human-gated\":$entry}}}"
  run feedback-question-design
  check "role label: present entry $entry fails" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
  check "role label: present entry $entry makes no gh call" '' "$(cat "$STUB/calls")"
done

# Idempotency.
setup '[{"name":"needs-human"}]' "$(bot_marker "$HEAD_A")"
run feedback-question-design
check "re-run on the same head: exit 0" 0 "$RC"
check "re-run on the same head: no write" 0 "$(writes)"

setup '[{"name":"needs-human"}]' "$(bot_marker "$HEAD_B")"
run feedback-question-design
check "labeled, marker for another head: comment only" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

# Another activity's escalation on the same head is recorded too, so
# gate-source.mjs reads every reason the label stands for.
setup '[{"name":"needs-human"}]' "$(bot_marker "$HEAD_A" feedback-disputed)"
run ci-fix-round-cap
check "labeled, same head, another reason: comment only" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"
has "labeled, same head, another reason: comment names the new reason" 'ci-fix-round-cap' "$STUB/bodies"

setup '[]' "$(bot_marker "$HEAD_A")"
run feedback-question-design
check "label removed by a human, same head: escalates again" \
  $'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

# Partial failure: a failed label write posts no comment; a failed comment
# write is retried; a retry run after the label landed posts exactly one comment.
LABEL_THEN_3_COMMENTS=$'POST repos/o/r/issues/42/labels\nPOST repos/o/r/issues/42/comments\nPOST repos/o/r/issues/42/comments\nPOST repos/o/r/issues/42/comments'
setup '[]' '[]'
touch "$STUB/fail_labels"
run feedback-question-design
check "label write fails: exit 1" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "label write fails: no comment posted" 0 "$(grep -c '^POST repos/o/r/issues/42/comments$' "$STUB/requests" || true)"

setup '[]' '[]'
echo 1 >"$STUB/fail_comments"
run feedback-question-design
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
  run feedback-question-design
  check "$1: comment write fails every attempt: exit 1" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
  check "$1: comment write fails every attempt: label on, three comment attempts" \
    "$LABEL_THEN_3_COMMENTS" "$(grep '^POST' "$STUB/requests")"
  printf '{"number":42,"labels":[{"name":"needs-human"}]}' >"$STUB/issue.json"
  echo 0 >"$STUB/fail_comments"
  : >"$STUB/requests"
  : >"$STUB/bodies"
}

exhausted "retry after a failed comment"
run feedback-question-design
check "retry after a failed comment: exit 0" 0 "$RC"
check "retry after a failed comment: one comment, no label" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

# A label left by a failed comment write is explained by the next run, on a later head too.
exhausted "label left, later head"
run feedback-question-design "$HEAD_B"
check "label left, later head: exit 0" 0 "$RC"
check "label left, later head: explains the label" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"
has "label left, later head: comment carries the later resume key" "resume-key=$HEAD_B" "$STUB/bodies"

setup '[{"name":"needs-human"}]' "$(comment "$MARKER"$'\n'"<!-- pr-unblock resume-key=$HEAD_A -->" someone User)"
run feedback-question-design
check "marker written by a user does not count" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

setup '[{"name":"needs-human"}]' "$(comment "$MARKER"$'\n'"<!-- pr-unblock resume-key=$HEAD_A -->" 'other-app[bot]' Bot)"
run feedback-question-design
check "marker written by another bot does not count" 'POST repos/o/r/issues/42/comments' "$(grep '^POST' "$STUB/requests")"

setup '[{"name":"needs-human"}]' "$(comment "$MARKER"$'\n'"<!-- pr-unblock resume-key=$HEAD_A -->"$'\n- Reason: `feedback-question-design`' 'other-app[bot]' Bot)"
LBL='other-app[bot]' run feedback-question-design
check "LANES_BOT_LOGIN names the lanes identity: no write" 0 "$(writes)"

# feedback-not-converging, a cap: no label; the comment names each open
# review thread, gives no count of its own (select's count, which also reads
# model check runs, is on the neutral checks), and names the write-access fix
# request that grants one more round.
ROUND='<!-- pr-unblock:address-feedback-round -->'
rounds_json=$(jq -n --arg r "$ROUND" '[range(4) | {body: ($r + "\npr-unblock / address-feedback finished round \(. + 1) of max 4 on x."), user: {login: "melodic-automation-lanes[bot]", type: "Bot"}}]')
setup '[]' "$rounds_json"
cat >"$STUB/threads.json" <<'EOF'
[{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
{"isResolved":false,"path":"src/a.js","line":5,"comments":{"nodes":[{"url":"https://github.com/o/r/pull/42#discussion_r1"}]}},
{"isResolved":true,"path":"src/b.js","line":7,"comments":{"nodes":[{"url":"https://github.com/o/r/pull/42#discussion_r2"}]}},
{"isResolved":false,"path":"docs/`odd`\nname.md","line":null,"comments":{"nodes":[{"url":"https://github.com/o/r/pull/42#discussion_r3"}]}},
{"isResolved":false,"path":"\n<!-- work-items:escalation lane=x -->.md","line":1,"comments":{"nodes":[{"url":"https://github.com/o/r/pull/42#discussion_r4"}]}}
]}}}}}]
EOF
run feedback-not-converging
check "not-converging: exit 0" 0 "$RC"
has "not-converging: says the cap and the fresh fixer round ran" 'not converging after the round cap and one fresh fixer round' "$STUB/bodies"
check "not-converging: no count read from the App's round markers alone" 0 "$(grep -c 'after 4 rounds' "$STUB/bodies" || true)"
has "not-converging: names an open thread" '- `src/a.js:5`: https://github.com/o/r/pull/42#discussion_r1' "$STUB/bodies"
has "not-converging: a path is shown without backticks or line breaks" '- `docs/odd name.md`: https://github.com/o/r/pull/42#discussion_r3' "$STUB/bodies"
check "not-converging: a path cannot open an HTML comment" 0 "$(grep -c '<!-- work-items:escalation lane=x' "$STUB/bodies" || true)"
has "not-converging: a path is shown without angle brackets" '- ` !-- work-items:escalation lane=x --.md:1`: https://github.com/o/r/pull/42#discussion_r4' "$STUB/bodies"
check "not-converging: a resolved thread is not named" 0 "$(grep -c 'src/b.js' "$STUB/bodies" || true)"
has "not-converging: a write-access fix request grants a round" 'PR-fix lane: please fix this finding' "$STUB/bodies"
check "not-converging: no label" 0 "$(grep -c '/labels' "$STUB/requests" || true)"
check "not-converging: no remove-the-label resume step" 0 "$(grep -c 'remove the' "$STUB/bodies" || true)"

# Every page of review threads is read: on a PR whose first page holds only
# resolved threads, an open thread on a later page is still named.
setup '[]' '[]'
cat >"$STUB/threads.json" <<'EOF'
[{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
{"isResolved":true,"path":"src/old.js","line":1,"comments":{"nodes":[{"url":"https://github.com/o/r/pull/42#discussion_r10"}]}}
],"pageInfo":{"hasNextPage":true,"endCursor":"c1"}}}}}},
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
{"isResolved":false,"path":"src/late.js","line":9,"comments":{"nodes":[{"url":"https://github.com/o/r/pull/42#discussion_r11"}]}}
],"pageInfo":{"hasNextPage":false,"endCursor":"c2"}}}}}}]
EOF
run feedback-not-converging
has "not-converging: asks for the next page by its cursor" 'endCursor=c1' "$STUB/calls"
has "not-converging: names an open thread from a later page" '- `src/late.js:9`: https://github.com/o/r/pull/42#discussion_r11' "$STUB/bodies"
check "not-converging: a later page's thread is not reported as none open" 0 "$(grep -c 'none open now' "$STUB/bodies" || true)"

# The read is bounded, since anyone who can comment can add threads: at most
# 10 pages (1,000 threads), and the comment says when more were not read.
setup '[]' '[]'
jq -n '[range(12) | {data: {repository: {pullRequest: {reviewThreads: {
  nodes: [{isResolved: false, path: "src/p\(.).js", line: 1, comments: {nodes: [{url: "https://github.com/o/r/pull/42#discussion_p\(.)"}]}}],
  pageInfo: {hasNextPage: true, endCursor: "c\(.)"}}}}}}]' >"$STUB/threads.json"
run feedback-not-converging
check "not-converging: reads at most 10 pages of review threads" 10 "$(grep -c '^GET graphql$' "$STUB/requests")"
has "not-converging: names a thread on the 10th page" '- `src/p9.js:1`' "$STUB/bodies"
check "not-converging: reads nothing past the 10th page" 0 "$(grep -c 'src/p10.js' "$STUB/bodies" || true)"
has "not-converging: says threads past the first 1,000 were not read" 'past the first 1,000 were not read' "$STUB/bodies"

# At most 20 open threads are listed, then how many more.
setup '[]' '[]'
jq -n '[{data: {repository: {pullRequest: {reviewThreads: {
  nodes: [range(25) | {isResolved: false, path: "src/t\(.).js", line: 1, comments: {nodes: [{url: "u\(.)"}]}}],
  pageInfo: {hasNextPage: false, endCursor: null}}}}}}]' >"$STUB/threads.json"
run feedback-not-converging
has "not-converging: lists the 20th open thread" '- `src/t19.js:1`: u19' "$STUB/bodies"
check "not-converging: lists no 21st open thread" 0 "$(grep -c 'src/t20.js' "$STUB/bodies" || true)"
has "not-converging: says how many more open threads there are" '- and 5 more' "$STUB/bodies"

setup '[]' '[]'
: >"$STUB/fail_graphql"
run feedback-not-converging
check "not-converging, threads unreadable: still escalates" 0 "$RC"
has "not-converging, threads unreadable: says so" 'could not be read' "$STUB/bodies"

# feedback-incomplete: the comment names each kept thread with no
# disposition, from the newest lanes App round marker on this head, in the
# shape publish-feedback.mjs undisposedLines writes (#8218's round 1, with a
# stand-in node id).
round_comment() { comment "$ROUND"$'\n'"pr-unblock / address-feedback finished round 1 of max 3 on $1."$'\n\nKept review threads with no disposition:\n'"$2" "${3:-melodic-automation-lanes[bot]}" "${4:-Bot}"; }
incomplete_json=$(jq -s add <<<"$(round_comment "$HEAD_B" '- `PRRT_old` (root comment 1)')
$(round_comment "$HEAD_A" '- `PRRT_8218` (root comment 4306751638)'$'\n- `PRRT_x` (root comment 5)\n- and 2 more\n- `PRRT_y` <!-- x --> (root comment 6)')
$(round_comment "$HEAD_A" '- `PRRT_human` (root comment 7)' someone User)")
setup '[]' "$incomplete_json"
GITHUB_SERVER_URL=https://github.com run feedback-incomplete
check "incomplete: exit 0" 0 "$RC"
has "incomplete: names the thread with no disposition" '- `PRRT_8218`: https://github.com/o/r/pull/42#discussion_r4306751638' "$STUB/bodies"
has "incomplete: names every such thread" '- `PRRT_x`: https://github.com/o/r/pull/42#discussion_r5' "$STUB/bodies"
has "incomplete: says how many more" '- and 2 more' "$STUB/bodies"
check "incomplete: a line of another shape is not copied" 0 "$(grep -c 'PRRT_y' "$STUB/bodies" || true)"
check "incomplete: a marker on another head is not read" 0 "$(grep -c 'PRRT_old' "$STUB/bodies" || true)"
check "incomplete: a marker another author wrote is not read" 0 "$(grep -c 'PRRT_human' "$STUB/bodies" || true)"
# feedback-incomplete routes to a failing status: the comment says how the
# run resumes, and no label goes on.
has "incomplete: says a new commit starts clean" 'A new commit to the branch starts clean' "$STUB/bodies"
check "incomplete: one comment, no label" 0 "$(grep -cE '^(POST|PATCH|PUT) [^ ]*/labels' "$STUB/requests" || true)"

setup '[]' "$(round_comment "$HEAD_B" '- `PRRT_old` (root comment 1)')"
run feedback-incomplete
check "incomplete, no marker on this head: still escalates" 0 "$RC"
has "incomplete, no marker on this head: points at the log" 'none named in the lane' "$STUB/bodies"

# Input validation.
setup '[]' '[]'
run repeat-cap not-a-sha
check "rejects a malformed head sha" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "malformed head sha: no gh call" '' "$(cat "$STUB/calls")"

# Each stop names its run, so a later stop on the same head edits the comment.
setup '[]' '[]'
GITHUB_RUN_ID=555 run ci-fix-round-cap
has "fail: names the run that stopped" '- Run: https://github.com/o/r/actions/runs/555' "$STUB/bodies"

# clear: a same-head attempt that did not stop posts success over the
# activity's failing status, and nothing when the newest one is not a failure
# or is another account's.
clear_case() {
  setup '[]' '[]'
  printf '%s' "$2" >"$STUB/statuses.json"
  set +e
  (cd "$STUB/ws" && env PATH="$TMP/bin:$PATH" STUB="$STUB" GH_TOKEN=t GITHUB_REPOSITORY=o/r HEAD_SHA="$HEAD_A" \
    ACTIVITY="$1" "$SUT" clear) >"$STUB/out" 2>&1
  RC=$?
  set -e
}
GHA='{"login":"github-actions[bot]"}'
clear_case address-feedback "[{\"context\":\"pr-unblock/address-feedback\",\"state\":\"failure\",\"creator\":$GHA}]"
check "clear: exit 0" 0 "$RC"
check "clear: success posted over the failure" "POST repos/o/r/statuses/$HEAD_A" "$(grep '^POST' "$STUB/requests")"
has "clear: state success" 'state=success' "$STUB/calls"
has "clear: the activity's context" 'context=pr-unblock/address-feedback' "$STUB/calls"
clear_case resolve-conflicts "[{\"context\":\"pr-unblock/conflict\",\"state\":\"failure\",\"creator\":$GHA}]"
has "clear: resolve-conflicts clears pr-unblock/conflict" 'context=pr-unblock/conflict' "$STUB/calls"
clear_case fix-ci "[{\"context\":\"pr-unblock/fix-ci\",\"state\":\"success\",\"creator\":$GHA},{\"context\":\"pr-unblock/fix-ci\",\"state\":\"failure\",\"creator\":$GHA}]"
check "clear: the newest is already success, nothing posted" 0 "$(writes)"
clear_case fix-ci "[{\"context\":\"pr-unblock/fix-ci\",\"state\":\"failure\",\"creator\":{\"login\":\"someone\"}}]"
check "clear: another account's status is not the lane's, nothing posted" 0 "$(writes)"
clear_case fix-ci "[{\"context\":\"pr-unblock/fix-ci\",\"state\":\"error\",\"creator\":$GHA}]"
has "clear: an error status is cleared as ci-status fails on it" 'context=pr-unblock/fix-ci' "$STUB/calls"
clear_case fix-ci "[{\"context\":\"pr-unblock/other\",\"state\":\"success\",\"creator\":$GHA}][{\"context\":\"pr-unblock/fix-ci\",\"state\":\"failure\",\"creator\":$GHA}]"
check "clear: a failure on a later page is cleared" "POST repos/o/r/statuses/$HEAD_A" "$(grep '^POST' "$STUB/requests")"
setup '[]' '[]'
: >"$STUB/fail_statuses"
set +e
(cd "$STUB/ws" && env PATH="$TMP/bin:$PATH" STUB="$STUB" GH_TOKEN=t GITHUB_REPOSITORY=o/r HEAD_SHA="$HEAD_A" \
  ACTIVITY=fix-ci "$SUT" clear) >"$STUB/out" 2>&1
RC=$?
set -e
check "clear: a refused status read fails" 1 "$RC"
has "clear: a refused status read is annotated with gh's message, one line" \
  "::error::cannot read the statuses of $HEAD_A: gh: API rate limit exceeded (HTTP 403)%0A100%25 used" "$STUB/out"
check "clear: a refused status read posts nothing" 0 "$(grep -c '^POST' "$STUB/requests" || true)"
has "clear: reads every page" '--paginate' "$STUB/calls"
clear_case fix-ci '[]'
check "clear: no status, nothing posted" 0 "$(writes)"
clear_case bogus '[]'
check "clear: an activity the table does not route fails" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
check "clear: an unknown activity makes no gh call" '' "$(cat "$STUB/calls")"

# Never touches the branch: no git, no contents API, no write outside the PR's issue.
for reason in feedback-question-design protected-path-conflict workflow-staged; do
  setup '[]' "$(comment '<!-- pr-unblock:lane-stopped activity=fix-ci -->'$'\nold' 'melodic-automation-lanes[bot]' Bot 9)"
  run "$reason"
  check "$reason: never runs git" 0 "$(grep -c '^git' "$STUB/calls" || true)"
  check "$reason: never calls the contents API" 0 "$(grep -c 'contents/' "$STUB/calls" || true)"
  check "$reason: writes only the issue, its comments and labels" 0 \
    "$(grep -vE '^(GET|POST) repos/o/r/issues/42(/comments(\?per_page=100)?|/labels)?$|^PATCH repos/o/r/issues/comments/9$' "$STUB/requests" | grep -c . || true)"
done

exit "$FAILED"
