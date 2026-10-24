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

# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"
export RUNNER_TEMP="$TMP_ROOT"
ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" || fail "the ci-status gh_read helper step is missing or fails"

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
if grep -qxF "      - name: Set up Node" "$WORKFLOW" && [[ "$(grep -nxF -e "      - name: Set up Node" -e "      - name: $NAME" "$WORKFLOW" | cut -d: -f2- | paste -sd'|')" == *"Set up Node|      - name: $NAME" ]]; then
  ok "a prior step pins Node right before the step"
else
  fail "no 'Set up Node' step right before the step"
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
# set. A files read answers STUB_FILES (a JSON array of [path,
# renamed-from or null, status] arrays, status renamed with a renamed-from
# path and modified otherwise) as the files API's rows, through the step's
# own --jq. A contents read of
# trusted-actors.json prints the working tree's list, or answers 404 when
# STUB_NO_ACTORS is set. An artifacts read by name prints the run ids
# STUB_ARTIFACTS (a JSON object of name to run ids) gives that name, through
# the step's own --jq, each artifact's id ten times its run's; a run read
# prints that id's entry of STUB_RUNS, or answers 404. An artifact archive
# holds STUB_RECORD as its verdict.json (one judging #1, closing, by
# default), or answers 404 when STUB_NO_RECORD is set; the closing-issues
# query answers STUB_CLOSING (#1 of o/r by default) through the step's --jq.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
rows() { jq -c '.[]' <<<"${1:-[]}"; }
discussion() {
  [[ "$(grep -cE '/(comments|reviews)\?' "$STUB_LOG")" -gt "${STUB_FAILS:-0}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
}
case "$*" in
"api graphql "*closingIssuesReferences*)
  closing=${STUB_CLOSING:-}
  [[ -n "$closing" ]] || closing='{"totalCount":1,"nodes":[{"number":1,"repository":{"nameWithOwner":"o/r"}}]}'
  jq -c --argjson closing "$closing" \
    '{data: {repository: {pullRequest: {closingIssuesReferences: $closing}}}}' <<<null | jq -c "${*: -1}"
  ;;
*/actions/artifacts/*/zip)
  [[ -z "${STUB_NO_RECORD:-}" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  record=${STUB_RECORD:-}
  [[ -n "$record" ]] || record='{"linked_issues":[{"number":1}],"spec_kind":"closes"}'
  python3 -c 'import io, sys, zipfile
buffer = io.BytesIO()
with zipfile.ZipFile(buffer, "w") as archive:
    archive.writestr("verdict.json", sys.argv[1])
sys.stdout.buffer.write(buffer.getvalue())' "$record"
  ;;
"api graphql "*)
  [[ -z "${STUB_DISARM_FAILS:-}" ]] || { echo 'gh: Resource not accessible by integration' >&2; exit 1; }
  echo '{"data":{}}'
  ;;
*/contents/.github/scripts/pr-merge/merge-holds.mjs*)
  [[ -z "${STUB_NO_MODULE:-}" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  cat "$STUB_MODULE"
  ;;
*/contents/docs/conventions/pr-pipeline.yaml*)
  [[ -z "${STUB_NO_CONFIG:-}" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  printf '%s\n' "$STUB_CONFIG"
  ;;
*/pulls/*/files\?*)
  jq -c '[.[] | {filename: .[0], previous_filename: .[1], status: (.[2] // (if .[1] then "renamed" else "modified" end))}]' <<<"$STUB_FILES" | jq -r "${*: -1}"
  ;;
*/contents/.github/standards/trusted-actors/trusted-actors.json*)
  [[ -z "${STUB_NO_ACTORS:-}" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  cat "$STUB_ACTORS"
  ;;
*/issues/*/comments\?*) discussion; rows "${STUB_ISSUE:-}" ;;
*/pulls/*/reviews\?*) discussion; rows "${STUB_REVIEWS:-}" ;;
*/pulls/*/comments\?*) discussion; rows "${STUB_INLINE:-}" ;;
*/actions/artifacts\?name=*)
  all="$*" name=${all##*actions/artifacts?name=}
  name=${name%%&*}
  # The step's own --jq filter, the last argument, runs over a listing that
  # also holds an expired artifact of that name and an unexpired one whose
  # name only starts with it, both of run 11, which neither may count.
  jq -c --arg name "$name" '{artifacts: ([.[$name][]? | {name: $name, id: (. * 10), expired: false, workflow_run: {id: .}}]
    + [{name: $name, id: 110, expired: true, workflow_run: {id: 11}}, {name: ($name + "-i1"), id: 110, expired: false, workflow_run: {id: 11}}])}' \
    <<<"${STUB_ARTIFACTS:-{\}}" | jq -r "${*: -1}"
  ;;
*/actions/runs/*)
  all="$*" id=${all##*actions/runs/}
  jq -ce --arg id "$id" '.[$id] // error' <<<"${STUB_RUNS:-{\}}" 2>/dev/null || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  ;;
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
  --argjson changed "${STUB_CHANGED:-1}" '{number: 7, node_id: "PR_7", user: $user, body: $body, head: {sha: "'"$SHA"'", ref: "work-resolve-issue/issue-1"}, base: {ref: $ref, sha: $sha}, changed_files: $changed,
    auto_merge: (if env.STUB_ARMED then {merge_method: "squash"} else null end)}'; }
comment() { jq -nc --arg login "$1" --arg type "${2:-User}" --arg assoc "$3" --arg at "$4" --arg body "$5" \
  '{user: {login: $login, type: $type}, author_association: $assoc, created_at: $at, body: $body}'; }
# approval <login> <id> <state> <at> <commit>: a review of a commit.
approval() { jq -nc --arg login "$1" --argjson id "$2" --arg state "$3" --arg at "$4" --arg commit "$5" \
  '{user: {login: $login, id: $id, type: "User"}, author_association: "OWNER", state: $state, submitted_at: $at, commit_id: $commit, body: ""}'; }
review() { jq -nc --arg login "$1" --arg assoc "$2" --arg at "$3" --arg body "$4" \
  '{user: {login: $login, type: "User"}, author_association: $assoc, submitted_at: $at, body: $body}'; }

# expect <label> <want-rc> <want-discussion-calls> [want-out]
# The event is pull_request with PR_NUMBER 7 unless EVENT/REF say otherwise.
expect() {
  local label="$1" want_rc="$2" want_calls="$3" out rc calls
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_MODULE="${STUB_MODULE:-$MODULE}" \
    GITHUB_EVENT_NAME="${EVENT:-pull_request}" EVENT_ACTION="${ACTION-synchronize}" GITHUB_REF="${REF:-refs/pull/7/merge}" PR_NUMBER="${PR_NUMBER-7}" \
    GITHUB_REPOSITORY=o/r GITHUB_API_URL=http://127.0.0.1:9 RUNNER_TEMP="$TMP_ROOT" GROUP_BASE_SHA="${GROUP_BASE_SHA-}" \
    LANES_DISABLED="${KILL-false}" LANES_REPO_DISABLED="${REPO_KILL-false}" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
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
export STUB_ACTORS="$ROOT/.github/standards/trusted-actors/trusted-actors.json"
export STUB_CONFIG=$'merge:\n  diff-check:\n    denied-paths: [docs/held/**]'
KYLE_VETO="$(comment kyle User MEMBER 2026-10-23T10:00:00Z 'Please do not merge this yet.')"

STUB_PULL="$(pull 'Closes #1')"
expect "a lanes App pull request with no hold passes" 0 3 "#7: no body hold, no member veto and no hold path"
STUB_PULL="$(pull 'Closes #1' '{"id":153232337,"login":"kyle-sexton","type":"User"}')"
expect "a person's pull request is left to pr-merge's gate, with no discussion read" 0 0 "not the lanes App's"
STUB_PULL="$(pull 'Closes #1' '{"id":1,"login":"melodic-automation-lanes[bot]","type":"User"}')"
expect "a user account with the lanes App's login is not the lanes App" 0 0 "not the lanes App's"

# The lanes kill switch stops every lanes App pull request, and only those.
for kill in "KILL=true" "KILL=" "REPO_KILL=true" "REPO_KILL=1"; do
  STUB_PULL="$(pull 'Closes #1')"
  export "${kill?}"
  expect "with $kill, a lanes App pull request fails" 1 0 "the lanes kill switch is on"
  STUB_PULL="$(pull 'Closes #1' '{"id":153232337,"login":"kyle-sexton","type":"User"}')"
  expect "with $kill, a person's pull request is not held by it" 0 0 "not the lanes App's"
  STUB_PULL="$(pull 'Closes #1' '{"id":49699333,"login":"dependabot[bot]","type":"Bot"}')"
  expect "with $kill, a Dependabot pull request is not held by it" 0 0 "not the lanes App's"
  STUB_PULL="$(pull 'Closes #1')"
  unset KILL REPO_KILL
done
# shellcheck disable=SC2016 # a literal workflow expression, not shell
if grep -qF 'LANES_DISABLED: ${{ vars.CLAUDE_LANES_DISABLED }}' <<<"$step" &&
  grep -qF 'LANES_REPO_DISABLED: ${{ vars.CLAUDE_LANES_REPO_DISABLED }}' <<<"$step"; then
  ok "the step reads both kill switches from the vars context"
else
  fail "the step does not read both kill switches from the vars context"
fi

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
expect "a file under the config's denied paths fails" 1 3 "::error::#7: it changes docs/held/a.md, a hold path; an approving review of this head by a person on the trusted-actor list lifts it"
STUB_FILES='[["docs/guide.md"],["docs/moved.md","docs/held/x.md"]]' STUB_PULL="$(STUB_CHANGED=2 pull 'Closes #1')"
expect "a rename away from a denied path fails on its old path" 1 3 "it changes docs/held/x.md, a hold path"
STUB_FILES='[["docs/held/x\n::stop-commands::t"]]' STUB_PULL="$(pull 'Closes #1')"
expect "a newline in a held file name cannot start a workflow command" 1 3 "it changes docs/held/x%0A::stop-commands::t, a hold path"
STUB_FILES='[["docs/guide.md"],["docs/held/.x.mjs"]]' STUB_PULL="$(STUB_CHANGED=2 pull 'Closes #1')"
expect "a dot-prefixed file under a denied tree fails" 1 3 "it changes docs/held/.x.mjs, a hold path"
# Owner direction 2026-10-24: no path holds for being trusted alone, and a
# manifest change is the security lane's finding. The lanes App's token never
# carries the workflows permission, so no lanes App push changes a workflow.
for path in CODEOWNERS docs/CODEOWNERS .gitmodules .github/standards/trusted-actors/README.md \
  .github/actions/resolve-config/resolve.mjs .github/actions/check-trusted-trigger/.x.mjs docs/conventions/pr-pipeline.yaml \
  plugins/p/.claude-plugin/plugin.json .github/workflows/x.yml .github/scripts/pr-merge/merge-holds.mjs .github/actions/other/action.yml; do
  STUB_FILES="[[\"$path\"]]" STUB_PULL="$(pull 'Closes #1')"
  expect "$path is no hold path" 0 3 "no hold path"
done
STUB_FILES='[[".claude-plugin/marketplace.json",null,"removed"]]' STUB_PULL="$(pull 'Closes #1')"
expect "a removed manifest is no hold" 0 3 "no hold path"
if grep -qF "[.filename, .previous_filename, .status]" <<<"$step"; then
  ok "the step hands merge-holds.mjs each file's status"
else
  fail "the step does not hand merge-holds.mjs each file's status"
fi
STUB_FILES='[["docs/held/x.md"]]'
KYLE_OK="$(approval kyle-sexton 153232337 APPROVED 2026-10-23T11:00:00Z "$SHA")"
STUB_REVIEWS="[$KYLE_OK]"
expect "a trusted person's approval of the head lifts a hold path" 0 3 "kyle-sexton approved this head, which lifts its hold path"
STUB_REVIEWS="[$(approval kyle-sexton 153232337 APPROVED 2026-10-23T11:00:00Z "$BASE")]"
expect "an approval of an earlier head does not lift it" 1 3 "it changes docs/held/x.md, a hold path"
STUB_REVIEWS="[$KYLE_OK,$(approval kyle-sexton 153232337 CHANGES_REQUESTED 2026-10-23T12:00:00Z "$SHA")]"
expect "a later request for changes by the same person takes the lift back" 1 3 "a hold path"
STUB_REVIEWS="[$KYLE_OK,$(approval kyle-sexton 153232337 COMMENTED 2026-10-23T12:00:00Z "$SHA")]"
expect "a later comment-only review keeps the lift" 0 3 "lifts its hold path"
STUB_REVIEWS="[$(approval someone 99 APPROVED 2026-10-23T11:00:00Z "$SHA")]"
expect "an approval by a person off the trusted-actor list does not lift it" 1 3 "a hold path"
STUB_REVIEWS="[$KYLE_OK]" STUB_PULL="$(pull $'Hold: x')"
expect "an approval lifts no body hold" 1 3 "its body holds it"
STUB_PULL="$(pull 'Closes #1')"
export STUB_NO_ACTORS=1
expect "an unreadable trusted-actor list fails closed" 1 0 "::error::could not read .github/standards/trusted-actors/trusted-actors.json at $BASE"
unset STUB_NO_ACTORS
STUB_REVIEWS=''
STUB_FILES='[["docs/guide.md"]]' STUB_CONFIG='merge: {}'
expect "a config with no denied paths holds no path" 0 3 "no hold path"
STUB_CONFIG=$'merge:\n  diff-check:\n    denied-paths: docs/held/**'
expect "denied paths that are not a list fail closed" 1 3 "the hold paths could not be read"
STUB_CONFIG=$'merge:\n  diff-check:\n    denied-paths: [docs/held/**]'
STUB_PULL="$(STUB_CHANGED=2 pull 'Closes #1')"
expect "a file list shorter than changed_files fails closed before the discussion" 1 0 "::error::GitHub listed fewer files than #7 changes"
STUB_PULL="$(pull 'Closes #1')"
export STUB_NO_CONFIG=1
expect "an unreadable config fails closed" 1 0 "::error::could not read docs/conventions/pr-pipeline.yaml at $BASE"
unset STUB_NO_CONFIG

# verifier runs: run <id> [path] [event] [branch] [status] [conclusion]
run() { jq -nc --argjson id "$1" --arg path "${2:-.github/workflows/pr-verify.yml}" --arg event "${3:-workflow_run}" \
  --arg branch "${4:-main}" --arg status "${5:-completed}" --arg conclusion "${6:-success}" \
  '{id: $id, path: $path, event: $event, head_branch: $branch, status: $status, conclusion: $conclusion,
    repository: {full_name: "o/r"}, head_repository: {full_name: "o/r"}}'; }
DIGEST="$(printf '%s' work-resolve-issue/issue-1 | sha256sum | cut -c1-16)"
OLD=fedcba9876543210fedcba9876543210fedcba98
# lookups: the artifact-by-name reads the last run made.
lookups() { grep -c 'actions/artifacts?name=' "$TMP_ROOT/log"; }
STUB_RUNS="$(jq -sc 'map({(.id | tostring): .}) | add' <<<"$(run 11)
$(run 12 .github/workflows/pr-verify.yml workflow_run main in_progress '')
$(run 13 .github/workflows/other.yml)
$(run 14 .github/workflows/pr-verify.yml pull_request)
$(run 15 .github/workflows/pr-verify.yml workflow_run work-resolve-issue/issue-1)
$(run 16 .github/workflows/pr-verify.yml workflow_run main completed failure)")"
# Run 17's read answers with run 11's record: another run than its artifact names.
STUB_RUNS="$(jq -c '. + {"17": .["11"]}' <<<"$STUB_RUNS")"
export STUB_RUNS

STUB_PULL="$(pull 'Closes #1')"
expect "a pull request event reads no verdict" 0 3 "no hold path"
if [[ "$(lookups)" -eq 0 ]] && ! grep -q 'actions/runs/' "$TMP_ROOT/log"; then
  ok "a pull request event makes no verdict read, so pr-verify can follow a green ci-status"
else
  fail "a pull request event read a verdict: '$(sort -u "$TMP_ROOT/log")'"
fi

# disarms: the auto-merge mutations the last run sent.
disarms() { grep -c '^api graphql .*disablePullRequestAutoMerge' "$TMP_ROOT/log"; }
# no_disarm <label>: the last run sent no disarm.
no_disarm() {
  if [[ "$(disarms)" -eq 0 ]]; then ok "$1"; else fail "$1: it sent a disarm"; fi
}
STUB_PULL="$(STUB_ARMED=1 pull 'Closes #1')"
expect "a push to an armed lanes App pull request turns its auto-merge off" 0 3 "#7: a push moved its head, so its native auto-merge is off"
if [[ "$(disarms)" -eq 1 ]] && grep -q -- '-f id=PR_7' "$TMP_ROOT/log"; then
  ok "the push disarms it by its node id with one mutation"
else
  fail "the push sent $(disarms) disarm(s): '$(sort -u "$TMP_ROOT/log")'"
fi
STUB_PULL="$(STUB_ARMED=1 pull 'Closes #1')"
export STUB_DISARM_FAILS=1
expect "a disarm that fails only warns, so a token that cannot disarm never holds a push red" 0 3 "::warning::could not turn off native auto-merge on #7 after a push to its head"
unset STUB_DISARM_FAILS
for action in edited labeled; do
  STUB_PULL="$(STUB_ARMED=1 pull 'Closes #1')" ACTION=$action
  expect "a $action event leaves an armed pull request armed" 0 3 "no hold path"
  no_disarm "a $action event sends no disarm"
done
unset ACTION
STUB_PULL="$(pull 'Closes #1')"
expect "a push to an unarmed pull request sends no mutation" 0 3 "no hold path"
no_disarm "an unarmed pull request is not disarmed"
STUB_PULL="$(STUB_ARMED=1 pull 'Closes #1' '{"id":153232337,"login":"kyle-sexton","type":"User"}')"
expect "a push to a person's armed pull request is left to them" 0 0 "not the lanes App's"
no_disarm "a person's pull request is not disarmed"
STUB_PULL="$(pull 'Closes #1')"

export EVENT=merge_group REF="$QUEUE" PR_NUMBER='' GROUP_BASE_SHA="$SHA" WANT_BASE="$SHA"
export STUB_ARTIFACTS="{\"pr-verify-7-$SHA-pass\":[11]}"
expect "in the merge queue, a pass at the head passes" 0 3 "#7: no verifier hold: pr-verify passed this head."
if [[ "$(lookups)" -eq 1 ]]; then
  ok "a plain-named pass ends the lookup after one name"
else
  fail "a plain-named pass took $(lookups) lookups"
fi
# The pass binds the link it judged (merge-holds.mjs linkHold): a body edited
# after arming to close or name another issue holds the group.
NO_CLOSING='{"totalCount":0,"nodes":[]}'
export STUB_CLOSING STUB_RECORD STUB_NO_RECORD
STUB_PULL="$(pull 'Refs: #1')" STUB_CLOSING="$NO_CLOSING" STUB_RECORD='{"linked_issues":[{"number":1}],"spec_kind":"refs"}'
expect "in the merge queue, a Refs pull request whose pass judged that issue passes" 0 3 "#7: no verifier hold: pr-verify passed this head."
STUB_PULL="$(pull 'Closes #2')" STUB_CLOSING='{"totalCount":1,"nodes":[{"number":2,"repository":{"nameWithOwner":"o/r"}}]}'
expect "in the merge queue, a Refs: #1 pass does not merge a body edited to Closes #2" 1 3 "its link changed since pr-verify passed it: it closes #2, and the pass judged #1 (refs)"
STUB_PULL="$(pull 'Closes #1')" STUB_CLOSING='' STUB_RECORD='{"linked_issues":[{"number":1}],"spec_kind":"refs"}'
expect "in the merge queue, a pass judged as a Refs slice does not cover the issue closed" 1 3 "its link changed since pr-verify passed it"
STUB_PULL="$(pull $'Refs: #1\nRefs: #3')" STUB_CLOSING="$NO_CLOSING"
# D:S9: a link of no issue or of several holds nothing; the fix loop
# rewrites it. One that drops the judged issue still holds.
expect "in the merge queue, a body naming two Refs issues passes" 0 3 "#7: no verifier hold: pr-verify passed this head."
STUB_PULL="$(pull 'Closes #1')" STUB_RECORD='' STUB_CLOSING='{"totalCount":2,"nodes":[{"number":1,"repository":{"nameWithOwner":"o/r"}},{"number":3,"repository":{"nameWithOwner":"o/r"}}]}'
expect "in the merge queue, a body closing the judged issue and another passes" 0 3 "#7: no verifier hold: pr-verify passed this head."
STUB_PULL="$(pull 'Closes #2')" STUB_CLOSING='{"totalCount":2,"nodes":[{"number":2,"repository":{"nameWithOwner":"o/r"}},{"number":3,"repository":{"nameWithOwner":"o/r"}}]}'
expect "in the merge queue, a body closing two issues but not the judged one holds" 1 3 "it closes #2, #3, and the pass judged #1"
STUB_CLOSING='' STUB_RECORD='{"verdict":"pass"}'
expect "in the merge queue, a record with no linked issues holds" 1 3 "its verifier pass's record could not be read"
STUB_RECORD='' STUB_NO_RECORD=1
expect "in the merge queue, a record that does not download fails closed" 1 3 "could not read the verdict of artifact 110"
STUB_NO_RECORD='' STUB_RECORD='{"linked_issues":[{"number":9}],"spec_kind":"closes"}' STUB_REVIEWS="[$(approval kyle-sexton 153232337 APPROVED 2026-10-23T11:00:00Z "$SHA")]"
expect "in the merge queue, a trusted approval of the head lifts a changed link" 0 3 "#7: no body hold, no member veto and no hold path."
STUB_RECORD='' STUB_REVIEWS=''
STUB_ARTIFACTS="{\"pr-verify-7-$SHA-pass-notes-$DIGEST\":[11]}"
expect "in the merge queue, a digest-named pass-notes at the head passes" 0 3 "no verifier hold: pr-verify passed this head"
STUB_ARTIFACTS='{}'
expect "in the merge queue, no verdict fails the group" 1 3 "::error::#7: pr-verify has not passed this head; wait for pr-verify to pass it"
if [[ "$(lookups)" -eq 4 ]]; then
  ok "no verdict looks up each pass name once"
else
  fail "no verdict took $(lookups) lookups"
fi
STUB_ARTIFACTS="{\"pr-verify-7-$OLD-pass\":[11],\"pr-verify-7-$SHA-fail\":[11]}"
expect "in the merge queue, a pass at an older head and a FAIL at this one fail the group" 1 3 "pr-verify has not passed this head"
STUB_ARTIFACTS="{\"pr-verify-8-$SHA-pass\":[11]}"
expect "in the merge queue, another pull request's pass fails the group" 1 3 "pr-verify has not passed this head"
for bad in 12:in-progress 13:another-workflow 14:a-pull-request-event 15:another-branch 16:a-failed-run 17:another-run-s-record 99:an-unreadable-run; do
  STUB_ARTIFACTS="{\"pr-verify-7-$SHA-pass\":[${bad%%:*}]}"
  if [[ ${bad%%:*} == 99 ]]; then
    expect "in the merge queue, a pass from ${bad#*:} fails closed" 1 3 "could not read run 99"
  else
    expect "in the merge queue, a pass from ${bad#*:} fails the group" 1 3 "pr-verify has not passed this head"
  fi
done
STUB_ARTIFACTS="{\"pr-verify-7-$SHA-pass\":[16],\"pr-verify-7-$SHA-pass-$DIGEST\":[11]}"
expect "in the merge queue, a failed run's pass does not hide a later name's good one" 0 3 "pr-verify passed this head"
# Run 17's read answers with run 11's record, which would count but for the
# id: the lookup must not stop on it, so the later real pass is still read.
STUB_ARTIFACTS="{\"pr-verify-7-$SHA-pass\":[17],\"pr-verify-7-$SHA-pass-$DIGEST\":[11]}"
expect "in the merge queue, another run's record does not end the lookup before a real pass" 0 3 "pr-verify passed this head"
if [[ "$(lookups)" -eq 2 ]]; then
  ok "a record whose run id differs from its artifact's does not end the lookup"
else
  fail "a mismatched run record ended the lookup after $(lookups) lookup(s)"
fi
STUB_ARTIFACTS="{\"pr-verify-7-$SHA-pass\":[13],\"pr-verify-7-$SHA-pass-$DIGEST\":[11]}"
expect "in the merge queue, another workflow's successful run does not end the lookup before a real pass" 0 3 "pr-verify passed this head"
if [[ "$(lookups)" -eq 2 ]]; then
  ok "the lookup ends at the first name holding a pr-verify pass"
else
  fail "the lookup took $(lookups) lookups"
fi
STUB_ARTIFACTS='{}' STUB_REVIEWS="[$(approval kyle-sexton 153232337 APPROVED 2026-10-23T11:00:00Z "$SHA")]"
expect "in the merge queue, a trusted approval of the head lifts a missing pass" 0 3 "no verifier hold: kyle-sexton approved this head"
STUB_REVIEWS="[$(approval kyle-sexton 153232337 APPROVED 2026-10-23T11:00:00Z "$OLD")]"
expect "in the merge queue, an approval of an earlier head lifts nothing" 1 3 "pr-verify has not passed this head"
STUB_REVIEWS=''
# Armed at a passing head, then pushed: the queue judges the new head, whose
# names no verdict carries yet.
STUB_ARTIFACTS="{\"pr-verify-7-$OLD-pass\":[11]}"
expect "in the merge queue, a push after a pass fails the group on the new head" 1 3 "pr-verify has not passed this head"
STUB_PULL="$(pull 'Closes #1' '{"id":153232337,"login":"kyle-sexton","type":"User"}')"
expect "in the merge queue, a person's pull request reads no verdict" 0 0 "not the lanes App's"
if [[ "$(lookups)" -eq 0 ]]; then
  ok "a person's pull request makes no verdict lookup"
else
  fail "a person's pull request made $(lookups) lookups"
fi
STUB_PULL="$(pull 'Closes #1')"
printf 'console.log("#7: no body hold, no member veto and no hold path.");\n' >"$TMP_ROOT/old.mjs"
STUB_ARTIFACTS="{\"pr-verify-7-$SHA-pass\":[11]}" STUB_MODULE="$TMP_ROOT/old.mjs"
expect "in the merge queue, a base module that ignores the verdicts fails closed" 1 3 "::error::merge-holds.mjs exited 0 without its verifier verdict"
unset STUB_MODULE
STUB_ARTIFACTS="{\"pr-verify-7-$SHA-pass\":[11]}"
STUB_PULL="$(pull $'Closes #1\nHold: owner call')"
expect "in the merge queue, a body hold fails the group" 1 3 "::error::#7: its body holds it"
STUB_PULL="$(pull 'Closes #1')" STUB_ISSUE="[$KYLE_VETO]"
expect "in the merge queue, a member's veto fails the group" 1 3 "kyle asked not to merge it"
STUB_ISSUE="[$KYLE_VETO,$(comment kyle User MEMBER 2026-10-23T11:00:00Z 'ok, merge it')]"
expect "in the merge queue, a lifted veto passes" 0 3
STUB_ISSUE='' STUB_FILES='[["docs/held/x.md"]]'
expect "in the merge queue, a hold path fails the group" 1 3 "it changes docs/held/x.md, a hold path"
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
