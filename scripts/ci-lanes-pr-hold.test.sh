#!/usr/bin/env bash
# Runs the `Fail a lanes App pull request its body or a member holds` step body
# of .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# Native auto-merge (pr-merge.yml's enable-auto-merge job) merges a lanes App
# pull request without pr-merge's gate, so ci-status holds it on the holds
# that gate honors: a body hold (a `Hold:` line or "do not merge"), a member's
# newest comment saying not to merge, and a changed or renamed-from path
# matching the merge lane's denied paths. It reads them live, on a pull
# request event and in the merge queue, runs the base commit's
# merge-holds.mjs, and fails closed when it cannot tell.
# test-scope: .github/workflows/pr-require-checks.yml .github/scripts/pr-merge/merge-holds.mjs docs/conventions/pr-pipeline.yaml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"
MODULE="$ROOT/.github/scripts/pr-merge/merge-holds.mjs"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Fail a lanes App pull request its body or a member holds'
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
if [[ "$step" == *"if: \${{ !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') }}"* ]]; then
  ok "step runs on pull_request and merge_group"
else
  fail "step lost its pull_request and merge_group condition"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
if [[ "$step" == *"github.event.pull_request.body"* ]]; then
  fail "step reads the body from the event payload, which a re-run replays stale"
else
  ok "step reads the body live"
fi
if [[ "$step" == *"GROUP_BASE_SHA: \${{ github.event.merge_group.base_sha }}"* && "$step" != *"pull_request.base"* ]]; then
  ok "step takes only the queue's base from the payload; a pull request's base is read live"
else
  fail "step reads a pull request's base from the payload"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line hold_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi
# The step names the lanes App by numeric id; it must be the trusted-actor
# entry for pr-pipeline.yaml's merge.agent-identity.
identity="$(sed -nE 's/^  agent-identity: (.+)$/\1/p' "$ROOT/docs/conventions/pr-pipeline.yaml")"
want_id="$(jq -r --arg login "$identity" '.. | objects | select(.login? == $login) | .id' "$ROOT/.github/standards/trusted-actors/trusted-actors.json")"
if [[ -n "$want_id" && "$(grep -c "lanes_app_id=$want_id\$" "$TMP_ROOT/body.sh")" -eq 1 ]]; then
  ok "step's lanes App id is merge.agent-identity's ($identity, $want_id)"
else
  fail "step's lanes App id is not $identity's trusted-actor id '$want_id'"
fi

# The stub logs its arguments. A pull read prints STUB_PULL. A contents read
# of merge-holds.mjs prints the working tree's module, or answers 404 when
# STUB_NO_MODULE is set. A discussion read fails its first STUB_FAILS calls,
# then prints each row of STUB_ISSUE, STUB_REVIEWS or STUB_INLINE (JSON
# arrays) as one line, as `--jq '.[] | @json'` does. A contents read of
# pr-pipeline.yaml prints STUB_CONFIG, or answers 404 when STUB_NO_CONFIG is
# set. A files read prints each row of STUB_FILES (a JSON array of
# [path, renamed-from?] arrays) as one line.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
rows() { jq -c '.[]' <<<"${1:-[]}"; }
discussion() {
  [[ "$(grep -cE '/(comments|reviews)\?' "$STUB_LOG")" -gt "${STUB_FAILS:-0}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
}
case "$*" in
*/contents/.github/scripts/pr-merge/merge-holds.mjs*)
  [[ -z "${STUB_NO_MODULE:-}" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  cat "$STUB_MODULE"
  ;;
*/contents/docs/conventions/pr-pipeline.yaml*)
  [[ -z "${STUB_NO_CONFIG:-}" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  printf '%s\n' "$STUB_CONFIG"
  ;;
*/pulls/*/files\?*) rows "$STUB_FILES" ;;
*/issues/*/comments\?*) discussion; rows "${STUB_ISSUE:-}" ;;
*/pulls/*/reviews\?*) discussion; rows "${STUB_REVIEWS:-}" ;;
*/pulls/*/comments\?*) discussion; rows "${STUB_INLINE:-}" ;;
*/pulls/*) printf '%s\n' "$STUB_PULL" ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

SHA=0123456789abcdef0123456789abcdef01234567
BASE=89abcdef0123456789abcdef0123456789abcdef
QUEUE="refs/heads/gh-readonly-queue/main/pr-7-$SHA"
LANES='{"id":337595936,"login":"melodic-automation-lanes[bot]","type":"Bot"}'
pull() { jq -nc --argjson user "${2:-$LANES}" --arg body "$1" --arg ref "${STUB_BASE_REF:-main}" --arg sha "${STUB_BASE_SHA:-$BASE}" \
  --argjson changed "${STUB_CHANGED:-1}" '{number: 7, user: $user, body: $body, base: {ref: $ref, sha: $sha}, changed_files: $changed}'; }
comment() { jq -nc --arg login "$1" --arg type "${2:-User}" --arg assoc "$3" --arg at "$4" --arg body "$5" \
  '{user: {login: $login, type: $type}, author_association: $assoc, created_at: $at, body: $body}'; }
review() { jq -nc --arg login "$1" --arg assoc "$2" --arg at "$3" --arg body "$4" \
  '{user: {login: $login, type: "User"}, author_association: $assoc, submitted_at: $at, body: $body}'; }

# expect <label> <want-rc> <want-discussion-calls> [want-out]
# The event is pull_request with PR_NUMBER 7 unless EVENT/REF say otherwise.
expect() {
  local label="$1" want_rc="$2" want_calls="$3" out rc calls
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_MODULE="${STUB_MODULE:-$MODULE}" \
    GITHUB_EVENT_NAME="${EVENT:-pull_request}" GITHUB_REF="${REF:-refs/pull/7/merge}" PR_NUMBER="${PR_NUMBER-7}" \
    GITHUB_REPOSITORY=o/r RUNNER_TEMP="$TMP_ROOT" GROUP_BASE_SHA="${GROUP_BASE_SHA-}" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -cE '/(comments|reviews)\?' "$TMP_ROOT/log")
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls discussion call(s) got $calls: '$(sort -u "$TMP_ROOT/log")'"
  elif [[ "$want_calls" -gt 0 ]] && ! grep -qxF "api -H Accept: application/vnd.github.raw+json repos/o/r/contents/.github/scripts/pr-merge/merge-holds.mjs?ref=${WANT_BASE:-$BASE}" "$TMP_ROOT/log"; then
    fail "$label: merge-holds.mjs was not read at the base commit: '$(sort -u "$TMP_ROOT/log")'"
  elif [[ -n "${4:-}" && "$out" != *"$4"* ]]; then
    fail "$label: output lacks '$4': '$out'"
  else
    ok "$label"
  fi
}

export STUB_PULL STUB_ISSUE='' STUB_REVIEWS='' STUB_INLINE='' STUB_FILES='[["docs/guide.md"]]'
export STUB_CONFIG=$'merge:\n  diff-check:\n    denied-paths: [docs/held/**]'
KYLE_VETO="$(comment kyle User MEMBER 2026-10-23T10:00:00Z 'Please do not merge this yet.')"

STUB_PULL="$(pull 'Closes #1')"
expect "a lanes App pull request with no hold passes" 0 3 "#7: no body hold, no member veto and no hold path"
STUB_PULL="$(pull 'Closes #1' '{"id":153232337,"login":"kyle-sexton","type":"User"}')"
expect "a person's pull request is left to pr-merge's gate, with no discussion read" 0 0 "not the lanes App's"
STUB_PULL="$(pull 'Closes #1' '{"id":1,"login":"melodic-automation-lanes[bot]","type":"User"}')"
expect "a user account with the lanes App's login is not the lanes App" 0 0 "not the lanes App's"

STUB_PULL="$(pull $'Closes #1\n\nHold: wait for the canary')"
expect "a Hold: line in the body fails" 1 3 "::error::#7: its body holds it"
STUB_PULL="$(pull $'Closes #1\r\n  hold: owner call')"
expect "an indented, lower-case hold line after a CRLF fails" 1 3 "its body holds it"
STUB_PULL="$(pull $'Closes #1\n\nDo not merge before Friday.')"
expect "'do not merge' in the body fails" 1 3 "its body holds it"
STUB_PULL="$(pull $'Closes #1\n\nThe threshold: unchanged')"
expect "a line that only contains 'hold:' later does not hold" 0 3

STUB_PULL="$(pull 'Closes #1')"
STUB_ISSUE="[$KYLE_VETO]"
expect "a member's veto comment fails, naming the member" 1 3 "::error::#7: kyle asked not to merge it"
STUB_ISSUE="[$(comment drive-by User NONE 2026-10-23T10:00:00Z 'do not merge')]"
expect "a NONE-association veto does not hold" 0 3
STUB_ISSUE="[$(comment outsider User CONTRIBUTOR 2026-10-23T10:00:00Z "don't merge")]"
expect "a CONTRIBUTOR veto does not hold" 0 3
STUB_ISSUE="[$(comment helper Bot MEMBER 2026-10-23T10:00:00Z 'do-not-merge')]"
expect "a bot's veto does not hold" 0 3
STUB_ISSUE="[$(comment owner User OWNER 2026-10-23T10:00:00Z "Don’t merge")]"
expect "an OWNER's curly-apostrophe veto holds" 1 3 "owner asked not to merge it"
STUB_ISSUE="[$KYLE_VETO,$(comment kyle User MEMBER 2026-10-23T11:00:00Z 'Go ahead now.')]"
expect "a later comment by the same member lifts the veto" 0 3
STUB_ISSUE="[$(comment kyle User MEMBER 2026-10-23T11:00:00Z 'Go ahead now.'),$KYLE_VETO]"
expect "the newest comment decides, not the listing order" 0 3
STUB_ISSUE="[$KYLE_VETO,$(comment other User COLLABORATOR 2026-10-23T11:00:00Z 'LGTM')]"
expect "another member's later comment does not lift it" 1 3 "kyle asked not to merge it"
STUB_ISSUE="[$KYLE_VETO]" STUB_REVIEWS="[$(review kyle MEMBER 2026-10-23T11:00:00Z '')]"
expect "a later review with no text does not lift it" 1 3 "kyle asked not to merge it"
STUB_ISSUE="[$KYLE_VETO]" STUB_REVIEWS="[$(review kyle MEMBER 2026-10-23T11:00:00Z 'Fine, ship it.')]"
expect "a later review with text lifts it" 0 3
STUB_ISSUE='[]' STUB_REVIEWS="[$(review kyle COLLABORATOR 2026-10-23T11:00:00Z 'do not merge')]"
expect "a review summary veto holds" 1 3 "kyle asked not to merge it"
STUB_REVIEWS='[]' STUB_INLINE="[$KYLE_VETO]"
expect "an inline review comment veto holds" 1 3 "kyle asked not to merge it"
STUB_INLINE='[]' STUB_ISSUE="[$KYLE_VETO,$(comment ana User OWNER 2026-10-23T09:00:00Z 'do not merge')]"
expect "every vetoing member is named, sorted" 1 3 "ana, kyle asked not to merge it"
STUB_ISSUE="[$KYLE_VETO]" STUB_PULL="$(pull $'Hold: x')"
expect "a body hold and a veto are both reported" 1 3 "kyle asked not to merge it"
STUB_ISSUE='' STUB_REVIEWS='' STUB_INLINE=''

STUB_PULL="$(pull 'Closes #1')"
STUB_FILES='[["docs/held/a.md"]]'
expect "a file under the config's denied paths fails" 1 3 "::error::#7: it changes docs/held/a.md, a hold path; a person merges it"
STUB_FILES='[["docs/guide.md"],["docs/moved.md",".github/workflows/x.yml"]]' STUB_PULL="$(STUB_CHANGED=2 pull 'Closes #1')"
expect "a rename away from a floor path fails on its old path" 1 3 "it changes .github/workflows/x.yml, a hold path"
STUB_FILES='[["docs/conventions/pr-pipeline.yaml"]]' STUB_PULL="$(pull 'Closes #1')"
expect "the pipeline config is held by the floor" 1 3 "it changes docs/conventions/pr-pipeline.yaml, a hold path"
STUB_FILES='[["docs/guide.md"]]' STUB_CONFIG='merge: {}'
expect "a config with no denied paths still holds nothing outside the floor" 0 3 "no hold path"
STUB_CONFIG=$'merge:\n  diff-check:\n    denied-paths: docs/held/**'
expect "denied paths that are not a list fail closed" 1 3 "the hold paths could not be read"
STUB_CONFIG=$'merge:\n  diff-check:\n    denied-paths: [docs/held/**]'
STUB_PULL="$(STUB_CHANGED=2 pull 'Closes #1')"
expect "a file list shorter than changed_files fails closed before the discussion" 1 0 "::error::GitHub listed fewer files than #7 changes"
STUB_PULL="$(pull 'Closes #1')"
export STUB_NO_CONFIG=1
expect "an unreadable config fails closed" 1 0 "::error::could not read docs/conventions/pr-pipeline.yaml at $BASE"
unset STUB_NO_CONFIG

export EVENT=merge_group REF="$QUEUE" PR_NUMBER='' GROUP_BASE_SHA="$SHA" WANT_BASE="$SHA"
STUB_PULL="$(pull $'Closes #1\nHold: owner call')"
expect "in the merge queue, a body hold fails the group" 1 3 "::error::#7: its body holds it"
STUB_PULL="$(pull 'Closes #1')" STUB_ISSUE="[$KYLE_VETO]"
expect "in the merge queue, a member's veto fails the group" 1 3 "kyle asked not to merge it"
STUB_ISSUE="[$KYLE_VETO,$(comment kyle User MEMBER 2026-10-23T11:00:00Z 'ok, merge it')]"
expect "in the merge queue, a lifted veto passes" 0 3
STUB_ISSUE='' STUB_FILES='[[".github/workflows/x.yml"]]'
expect "in the merge queue, a hold path fails the group" 1 3 "it changes .github/workflows/x.yml, a hold path"
STUB_FILES='[["docs/guide.md"]]'
export REF="refs/heads/main"
expect "a merge-group ref with no pull request fails closed without a call" 1 0 "::error::cannot read a pull request number"
export STUB_ISSUE='[]' REF="$QUEUE" GROUP_BASE_SHA=main
expect "a queue base that is not a commit SHA fails closed without a call" 1 0 "::error::the base commit 'main' is not a commit SHA"
unset EVENT REF PR_NUMBER GROUP_BASE_SHA WANT_BASE

STUB_PULL="$(pull 'Closes #1')"
export STUB_FAILS=1
expect "a transient discussion read failure is retried" 0 4
export STUB_FAILS=3
expect "an unreadable discussion fails closed" 1 3 "::error::could not read the issues/7/comments of #7"
unset STUB_FAILS
printf 'process.exitCode = 0;\n' >"$TMP_ROOT/silent.mjs"
export STUB_MODULE="$TMP_ROOT/silent.mjs"
expect "a module that exits 0 without its verdict fails closed" 1 3 "::error::merge-holds.mjs exited 0 without its verdict"
unset STUB_MODULE
export STUB_NO_MODULE=1
expect "a base with no merge-holds.mjs fails closed" 1 0 "::error::could not read .github/scripts/pr-merge/merge-holds.mjs at $BASE"
unset STUB_NO_MODULE
STUB_PULL="$(STUB_BASE_SHA=main pull 'Closes #1')"
expect "a live base that is not a commit SHA fails closed without a call" 1 0 "::error::the base commit 'main' is not a commit SHA"
STUB_PULL="$(STUB_BASE_REF=attacker STUB_BASE_SHA="$SHA" pull $'Hold: x')"
expect "a pull request into another branch runs no module from that branch" 0 0 "is not into main"
STUB_PULL='{"number":7,"message":"Server Error"}'
expect "a pull read with no author fails closed" 1 0 "::error::the author of #7 could not be read"
STUB_PULL="$(pull 'Closes #1')"
export PR_NUMBER='7; rm -rf /'
expect "a pull request number that is not a number fails closed" 1 0 "is not a number"
unset PR_NUMBER

test_harness::report
