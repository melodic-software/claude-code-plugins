#!/usr/bin/env bash
# Runs the `Fail a pull request carrying the human-gated label` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# On a pull_request event, contract-only runs included, ci-status fails while
# the pull request carries the human-gated label the base commit's
# .work-item-tracker.json names (default `needs-human`), read from the base
# commit's sparse checkout; the labels are read live from the API.
# The error names the reason from the newest review-lane hold comment, and says
# that removing the label approves. It fails closed when it cannot tell.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"
export RUNNER_TEMP="$TMP_ROOT"
ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" budget || fail "the ci-status gh_read helper step is missing or fails"

NAME='Fail a pull request carrying the human-gated label'
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
# Every pull_request run, contract-only included, and after a failed earlier
# step, so the hold is never hidden. A draft's ci-status passes by design
# (`Note a draft`), so the step makes no read there; the ready_for_review run
# judges the label.
if [[ "$step" == *"if: \${{ !cancelled() && github.event_name == 'pull_request' && github.event.pull_request.draft != true }}"* ]]; then
  ok "step runs on every pull_request run that is not cancelled or a draft"
else
  fail "step lost its pull_request condition or its draft skip"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
if [[ "$step" == *$'\n        id: human_gated\n'* ]]; then
  ok "step carries the id the hold-lift step reads its outputs by"
else
  fail "step lost its human_gated id"
fi
if [[ "$step" == *"BASE_CONFIG: \${{ steps.base_config.outcome == 'success' && format('{0}/base-config', github.workspace) || '' }}"* ]]; then
  ok "step reads the tracker config from the base checkout, and none when it failed"
else
  fail "step does not read the tracker config from the base_config checkout"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line hold_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi
# The config comes from a sparse checkout of the commit hold_ref resolves:
# never the head, never a persisted credential, never an empty ref (which
# checks out the event's ref, the pull request's own merge commit), and before
# every step that reads it.
checkout="$(awk '$0 == "      - name: Check out the base commit'"'"'s hold config" { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
# shellcheck disable=SC2016 # workflow literals to match, not shell expansions
for line in $'\n        id: base_config\n' 'continue-on-error: true' \
  "if: \${{ !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') && steps.hold_ref.outputs.sha != '' }}" \
  'ref: ${{ steps.hold_ref.outputs.sha }}' \
  'persist-credentials: false' '/.work-item-tracker.json' '/.github/standards/trusted-actors/trusted-actors.json' \
  'sparse-checkout-cone-mode: false' 'path: base-config'; do
  if [[ "$checkout" == *"$line"* ]]; then ok "the base checkout carries '${line//$'\n'/}'"; else fail "the base checkout lost '${line//$'\n'/}'"; fi
done
order="$(grep -nE "^  ci-status:$|^      - name: (Check out the base commit's hold config|Clear a cost-only review hold the owner decided)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line checkout_line cost_line <<<"$order"
if [[ -n "${cost_line:-}" && "$job_line" -lt "$checkout_line" && "$checkout_line" -lt "$cost_line" ]]; then
  ok "the base checkout sits in ci-status before the first step that reads it"
else
  fail "the base checkout is not in ci-status before the cost-hold step (lines: $order)"
fi

# hold_ref resolves the commit the hold config is read at: a pull request into
# the default branch reads the branch's tip at run time, so a re-run (which
# replays the event and its stale base.sha) still sees a policy merged since;
# any other base, and a merge group, keep the event's base SHA.
REF_NAME="Resolve the hold config's commit"
ref_step="$(awk -v name="      - name: $REF_NAME" '$0 == name { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$ref_step" >"$TMP_ROOT/hold-ref.sh"
# shellcheck disable=SC2016 # workflow literals to match, not shell expansions
for line in $'\n        id: hold_ref\n' \
  "if: \${{ !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') }}" \
  'BASE_REF: ${{ github.event.pull_request.base.ref }}' \
  'DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}' \
  'BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.merge_group.base_sha }}'; do
  if [[ "$ref_step" == *"$line"* ]]; then ok "hold_ref carries '${line//$'\n'/}'"; else fail "hold_ref lost '${line//$'\n'/}'"; fi
done
if [[ "$ref_step" == *"continue-on-error"* ]]; then
  fail "hold_ref must not continue on error: the checkout's guard reads its output"
else
  ok "hold_ref carries no continue-on-error"
fi
# shellcheck disable=SC2016 # a workflow expression to match, not a shell expansion
if [[ -s "$TMP_ROOT/hold-ref.sh" ]] && ! grep -q '\${{' "$TMP_ROOT/hold-ref.sh"; then
  ok "hold_ref's run body takes every event value through env"
else
  fail "hold_ref has no run body, or inlines an expression in it"
fi
order="$(grep -nE "^      - name: ($REF_NAME|Check out the base commit's hold config)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r ref_line checkout_line <<<"$order"
if [[ -n "${checkout_line:-}" && "$ref_line" -lt "$checkout_line" ]]; then
  ok "hold_ref sits before the checkout that reads it"
else
  fail "hold_ref is not before the base checkout (lines: $order)"
fi

mkdir -p "$TMP_ROOT/git-bin"
cat >"$TMP_ROOT/git-bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_LOG"
[[ -z "${STUB_LS-}" ]] || printf '%b' "$STUB_LS"
exit "${STUB_GIT_RC:-0}"
EOF
chmod +x "$TMP_ROOT/git-bin/git"
REF_BASE=1111111111111111111111111111111111111111
REF_TIP=2222222222222222222222222222222222222222
REF_DECOY=3333333333333333333333333333333333333333
# hold_ref_case LABEL EVENT BASE_REF WANT_RC WANT_SHA WANT_GIT_CALLS WANT_WARNING
hold_ref_case() {
  local label="$1" out rc sha calls
  : >"$TMP_ROOT/hold-ref.out"
  : >"$TMP_ROOT/git.log"
  out="$(cd "$TMP_ROOT" && PATH="$TMP_ROOT/git-bin:$PATH" GIT_LOG="$TMP_ROOT/git.log" GITHUB_OUTPUT="$TMP_ROOT/hold-ref.out" \
    GITHUB_REPOSITORY=melodic-software/claude-code-plugins RUNNER_TEMP="$TMP_ROOT" \
    EVENT="$2" BASE_REF="$3" DEFAULT_BRANCH=main BASE_SHA="${REF_BASE_SHA-$REF_BASE}" \
    bash -e "$TMP_ROOT/hold-ref.sh" 2>&1)" && rc=0 || rc=$?
  sha="$(sed -n 's/^sha=//p' "$TMP_ROOT/hold-ref.out")"
  calls="$(grep -c . "$TMP_ROOT/git.log")"
  if [[ "$rc" == "$4" && "$sha" == "$5" && "$calls" == "$6" ]] &&
    { [[ -z "$7" ]] && [[ "$out" != *"::warning::"* ]] || [[ -n "$7" && "$out" == *"$7"* ]]; }; then
    ok "hold_ref: $label"
  else
    fail "hold_ref: $label (rc=$rc sha='$sha' git calls=$calls out: $out)"
  fi
}
STUB_LS="$REF_TIP\trefs/heads/main\n" hold_ref_case "a pull request into the default branch reads its tip" \
  pull_request main 0 "$REF_TIP" 1 ""
if grep -qxF -e "-C $TMP_ROOT ls-remote https://github.com/melodic-software/claude-code-plugins refs/heads/main" "$TMP_ROOT/git.log"; then
  ok "hold_ref asks the public remote for the default branch, outside any checkout"
else
  fail "hold_ref's ls-remote call is not the expected one: $(cat "$TMP_ROOT/git.log")"
fi
STUB_LS="$REF_TIP\trefs/heads/main\n" hold_ref_case "a pull request into another branch keeps the base SHA" \
  pull_request release/1 0 "$REF_BASE" 0 ""
STUB_LS="$REF_TIP\trefs/heads/main\n" hold_ref_case "a merge group keeps the base SHA" \
  merge_group "" 0 "$REF_BASE" 0 ""
STUB_GIT_RC=128 hold_ref_case "a failed ls-remote falls back to the base SHA with a warning" \
  pull_request main 0 "$REF_BASE" 1 "::warning::"
STUB_LS="not-a-sha\trefs/heads/main\n" hold_ref_case "a non-hex answer falls back to the base SHA with a warning" \
  pull_request main 0 "$REF_BASE" 1 "::warning::"
STUB_LS="$REF_DECOY\trefs/heads/x/refs/heads/main\n" hold_ref_case "a tail-matching ref is not the default branch" \
  pull_request main 0 "$REF_BASE" 1 "::warning::"
STUB_LS="$REF_DECOY\trefs/heads/x/refs/heads/main\n$REF_TIP\trefs/heads/main\n" hold_ref_case "the exact ref wins over a tail match" \
  pull_request main 0 "$REF_TIP" 1 ""
REF_BASE_SHA=main hold_ref_case "a base that is not a commit SHA outputs no ref" \
  pull_request release/1 1 "" 0 ""
gate="$(awk '/^  ci-status:$/ { on = 1; next } on && /^    if: / { print; exit }' "$WORKFLOW")"
if [[ "$gate" == "    if: \${{ !cancelled() }}" ]]; then
  ok "ci-status carries no contract-only gate, so the step runs on label events"
else
  fail "ci-status gained a gate that could skip the hold: '$gate'"
fi

# The base commit's config is a fixture directory: STUB_TRACKER is its
# .work-item-tracker.json (absent when unset), and STUB_CHECKOUT_FAILED leaves
# BASE_CONFIG empty, as a failed checkout does. The gh stub logs its
# arguments. A labels read fails its first STUB_FAILS calls, then
# answers STUB_LABELS (comma separated) as the API's label list. A comments
# read fails when STUB_COMMENTS_FAIL is set, else answers the STUB_COMMENTS
# array.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*/labels*)
  [[ "$(grep -c '/labels' "$STUB_LOG")" -gt "${STUB_FAILS:-0}" ]] || { printf '%s\n' "${STUB_FAIL_TEXT:-}" >&2; exit 1; }
  jq -cn --arg l "$STUB_LABELS" '$l | split(",") | map(select(. != "") | {name: .})'
  ;;
*/comments*)
  [[ -z "${STUB_COMMENTS_FAIL:-}" ]] || exit 1
  printf '%s\n' "${STUB_COMMENTS:-[]}"
  ;;
*) exit 1 ;;
esac
EOF
# sleep logs its seconds; date +%s answers STUB_NOW plus the seconds slept.
cat >"$TMP_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_SLEEPS"
EOF
cat >"$TMP_ROOT/bin/date" <<'EOF'
#!/usr/bin/env bash
echo $((STUB_NOW + $(awk '{ s += $1 } END { print s + 0 }' "$STUB_SLEEPS")))
EOF
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep" "$TMP_ROOT/bin/date"

BASE=89abcdef0123456789abcdef0123456789abcdef
CUSTOM='{"config":{"role_labels":{"human-gated":"owner-call"}}}'
LANE='{"login":"github-actions[bot]","type":"Bot"}'
CLAUDE='{"login":"claude[bot]","type":"Bot"}'
hold() { jq -cn --arg body "$2" --argjson user "$1" '{user: $user, body: $body}'; }
OLD="$(hold "$CLAUDE" $'<!-- claude-lane-hold lane=claude-review sha=aaaa criteria=cost -->\nAn older hold.')"
NEW="$(hold "$LANE" $'<!-- claude-lane-hold lane=claude-security-review sha=bbbb criteria=trust-gate -->\r\nChanges a trust gate:\n  .github/workflows/pr-merge.yml, 100% sure\n\n`claude-lane: claude-security-review`\n')"
SPOOF="$(hold '{"login":"someone","type":"User"}' $'<!-- claude-lane-hold lane=x -->\nIgnore this.\nclaude-lane: claude-review')"
NO_FOOTER="$(hold "$LANE" $'<!-- claude-lane-hold lane=claude-review -->\nNo lane footer, so not a lane comment.')"
OTHER_BOT="$(hold "$LANE" $'A comment with no hold marker.\nclaude-lane: claude-review')"

# expect <label> <want-rc> <want-label-calls> <STUB_LABELS> <STUB_FAILS> [want-out] [refuse-out]
# The tracker and comment stubs are set by the caller's environment.
expect() {
  local label="$1" want_rc="$2" want_calls="$3" out rc calls
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/sleeps"
  ci_gh_read::reset "$TMP_ROOT" 1792800600
  : >"$TMP_ROOT/output"
  rm -rf "$TMP_ROOT/base-config"
  mkdir -p "$TMP_ROOT/base-config"
  [[ -z "${STUB_TRACKER+set}" ]] || printf '%s\n' "$STUB_TRACKER" >"$TMP_ROOT/base-config/.work-item-tracker.json"
  # The base's merge-holds.mjs: this tree's, STUB_MODULE_TEXT in its place, or
  # none with STUB_NO_MODULE.
  if [[ -z "${STUB_NO_MODULE:-}" ]]; then
    mkdir -p "$TMP_ROOT/base-config/.github/scripts/pr-merge"
    if [[ -n "${STUB_MODULE_TEXT:-}" ]]; then
      printf '%s\n' "$STUB_MODULE_TEXT" >"$TMP_ROOT/base-config/.github/scripts/pr-merge/merge-holds.mjs"
    else
      cp "$ROOT/.github/scripts/pr-merge/merge-holds.mjs" "$TMP_ROOT/base-config/.github/scripts/pr-merge/"
    fi
  fi
  if [[ -n "${STUB_PIPELINE:-}" ]]; then
    mkdir -p "$TMP_ROOT/base-config/docs/conventions"
    printf '%s\n' "$STUB_PIPELINE" >"$TMP_ROOT/base-config/docs/conventions/pr-pipeline.yaml"
  fi
  local config="$TMP_ROOT/base-config"
  [[ -z "${STUB_CHECKOUT_FAILED:-}" ]] || config=
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_SLEEPS="$TMP_ROOT/sleeps" STUB_NOW="${STUB_NOW_AT:-1792800000}" STUB_LABELS="$4" STUB_FAILS="$5" PR_NUMBER=6419 \
    GITHUB_REPOSITORY=o/r RUNNER_TEMP="$TMP_ROOT" GITHUB_OUTPUT="$TMP_ROOT/output" BASE_SHA="${BASE_SHA-$BASE}" \
    BASE_CONFIG="$config" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -c '/labels' "$TMP_ROOT/log")
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls labels call(s) got $calls"
  elif [[ "$calls" -gt 0 && "$(grep '/labels' "$TMP_ROOT/log" | sort -u)" != "api repos/o/r/issues/6419/labels?per_page=100 --paginate" ]]; then
    fail "$label: unexpected labels call '$(grep '/labels' "$TMP_ROOT/log" | sort -u)'"
  elif grep -q '/contents/' "$TMP_ROOT/log"; then
    fail "$label: the tracker config was read through the API: '$(sort -u "$TMP_ROOT/log")'"
  elif [[ -n "${6:-}" && "$out" != *"$6"* ]]; then
    fail "$label: output lacks '$6': '$out'"
  elif [[ -n "${7:-}" && "$out" == *"$7"* ]]; then
    fail "$label: output has '$7': '$out'"
  else
    ok "$label"
  fi
}

APPROVE="Removing the label approves this pull request; ci-status re-runs on the unlabel."

expect "an unlabeled pull request passes" 0 1 "enhancement,do-not-merge" 0 "#6419 carries no 'needs-human' label."
if grep -q '/comments' "$TMP_ROOT/log"; then fail "comments are read only when the label is on"; else ok "comments are read only when the label is on"; fi
if [[ "$(cat "$TMP_ROOT/output")" == $'label=needs-human\nheld=false' ]]; then
  ok "an unlabeled pull request outputs the label and held=false"
else
  fail "an unlabeled pull request's outputs: '$(cat "$TMP_ROOT/output")'"
fi
expect "a pull request with no labels passes" 0 1 "" 0
expect "a label that only contains the name does not hold" 0 1 "needs-human-later,not-needs-human" 0
expect "the outside-actor label alone fails" 1 1 "ci,security: outside-actor" 0 \
  "::error::#6419 carries 'security: outside-actor': someone outside the organization wrote on it"
if grep -qxF 'held=false' "$TMP_ROOT/output"; then
  ok "an outside-actor hold without the human-gated label still outputs held=false"
else
  fail "an outside-actor hold's outputs: '$(cat "$TMP_ROOT/output")'"
fi
export STUB_MODULE_TEXT='export const humanGatedLabel = () => "needs-human";'
expect "a base module that exports no outside-actor label names no such hold" 0 1 "security: outside-actor" 0 "#6419 carries no 'needs-human' label."
unset STUB_MODULE_TEXT
expect "needs-human with no hold comment fails without a reason" 1 1 "ci,needs-human" 0 \
  "::error::#6419 carries 'needs-human'. $APPROVE"
if [[ "$(cat "$TMP_ROOT/output")" == "label=needs-human" ]]; then
  ok "a held pull request outputs the label and no held=false"
else
  fail "a held pull request's outputs: '$(cat "$TMP_ROOT/output")'"
fi

export STUB_COMMENTS="[$OLD,$NEW,$SPOOF,$NO_FOOTER,$OTHER_BOT]"
expect "the newest lane hold comment gives the reason, without its footer" 1 1 "needs-human" 0 \
  "::error::#6419 carries 'needs-human' (Changes a trust gate: .github/workflows/pr-merge.yml, 100%25 sure). $APPROVE" "An older hold"
expect "a hold comment from a person is not read" 1 1 "needs-human" 0 "" "Ignore this"
expect "a github-actions[bot] hold comment with no lane footer is not read" 1 1 "needs-human" 0 "" "No lane footer"
export STUB_COMMENTS="[$NEW,$OLD]"
expect "a claude[bot] hold comment gives the reason" 1 1 "needs-human" 0 "(An older hold.). $APPROVE"
# pr-merge's refusal (enable-auto-merge.mjs refusalBody), a person's: the
# attend-queue marker, then the reasons marker, the reasons fenced. Newer
# than the security hold, so it names the hold that set the label (#10224).
APP='{"login":"melodic-automation-lanes[bot]","type":"Bot"}'
REFUSAL_BODY=$'<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-risk -->\nUnattended merge: native auto-merge leaves this pull request unarmed at head `bbbb`. A person must clear this reason, so the pr-merge lane added the `needs-human` label: fix the reason, then remove the label, and the next scheduled run judges it again.\n\n```text\nit changes docs/held.md, a hold path\npr-merge\'s gate holds it on its risk score (cost-review-required: infra/main.tf)\n```'
REFUSAL="$(hold "$APP" "$REFUSAL_BODY")"
export STUB_COMMENTS="[$NEW,$REFUSAL]" STUB_PIPELINE=$'merge:\n  agent-identity: melodic-automation-lanes[bot]'
expect "a newer pr-merge refusal beats an older security hold, naming its fenced reasons" 1 1 "needs-human" 0 \
  "(it changes docs/held.md, a hold path pr-merge's gate holds it on its risk score (cost-review-required: infra/main.tf)). $APPROVE" "Changes a trust gate"
# A reason line past 100 columns wraps at a space, its continuation indented
# two spaces, and more than 20 lines fold into <details>: the reason reads
# back as one line either way.
WRAPPED_BODY=$'<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-risk -->\nUnattended merge: native auto-merge leaves this pull request unarmed at head `bbbb`. A person must clear this reason, so the pr-merge lane added the `needs-human` label: fix the reason, then remove the label, and the next scheduled run judges it again.\n\n```text\npr-merge\'s gate holds it on its risk score (manifest-review-required:\n  plugins/a/.claude-plugin/plugin.json: hooks)\n```'
WRAPPED="$(hold "$APP" "$WRAPPED_BODY")"
export STUB_COMMENTS="[$NEW,$WRAPPED]" STUB_PIPELINE=$'merge:\n  agent-identity: melodic-automation-lanes[bot]'
expect "a wrapped pr-merge refusal names its reason on one line" 1 1 "needs-human" 0 \
  "(pr-merge's gate holds it on its risk score (manifest-review-required: plugins/a/.claude-plugin/plugin.json: hooks)). $APPROVE" "Changes a trust gate"
FOLDED_BODY="${WRAPPED_BODY/$'```text'/$'<details><summary>Its reasons (21 lines)</summary>\n\n```text'}"$'\n\n</details>'
FOLDED="$(hold "$APP" "$FOLDED_BODY")"
export STUB_COMMENTS="[$NEW,$FOLDED]"
expect "a folded pr-merge refusal names its reason too" 1 1 "needs-human" 0 \
  "(pr-merge's gate holds it on its risk score (manifest-review-required: plugins/a/.claude-plugin/plugin.json: hooks)). $APPROVE" "Its reasons"
export STUB_COMMENTS="[$REFUSAL,$NEW]"
expect "a newer security hold beats an older pr-merge refusal" 1 1 "needs-human" 0 "(Changes a trust gate:" "risk score"
# A lane's refusal (no attend-queue marker) set no label, so a newer one
# never names the hold that did.
LANE_REFUSAL="$(hold "$APP" $'<!-- babysit-merge-risk -->\nUnattended merge: native auto-merge leaves this pull request unarmed at head `bbbb`. The lanes clear this reason on their own; the next scheduled run judges it again.\n\n```text\nits verifier verdict is missing\n```\n<!-- pr-merge-unarmed-since head=bbbb at=2026-10-23T10:00:00Z -->')"
export STUB_COMMENTS="[$NEW,$LANE_REFUSAL]"
expect "a newer pr-merge lane refusal does not name the label's hold" 1 1 "needs-human" 0 "(Changes a trust gate:" "verdict is missing"
export STUB_COMMENTS="[$NEW,$REFUSAL]"
OTHER_REFUSAL="$(hold "$LANE" "$REFUSAL_BODY")"
export STUB_COMMENTS="[$NEW,$OTHER_REFUSAL]"
expect "a refusal-shaped comment by another bot is not read" 1 1 "needs-human" 0 "(Changes a trust gate:" "risk score"
export STUB_COMMENTS="[$NEW,$REFUSAL]"
unset STUB_PIPELINE
expect "with merge.agent-identity unread, only the review lanes' holds are read" 1 1 "needs-human" 0 "(Changes a trust gate:" "risk score"
LONG="$(printf 'x%.0s' {1..400})"
STUB_COMMENTS="[$(hold "$CLAUDE" "<!-- claude-lane-hold lane=claude-review -->
$LONG")]"
expect "a long reason is cut to 300 characters" 1 1 "needs-human" 0 "(${LONG:0:300}). $APPROVE"
export STUB_COMMENTS_FAIL=1
expect "an unreadable comment list still fails, without a reason" 1 1 "needs-human" 0 "::error::#6419 carries 'needs-human'. $APPROVE"
unset STUB_COMMENTS STUB_COMMENTS_FAIL

expect "a transient label read failure is retried" 1 2 "needs-human" 1

# A paginated read's rate limit stops every pool (the api-budget rate guard):
# for an hour on a primary limit, for the documented minute on a secondary
# one. Its headers are unseen, so the stop is a guess and gh_read takes no
# wait: the read fails closed, and the caller's retries make no call. Any
# other error keeps the caller's retries and is never waited on.
sleeps() { paste -sd' ' "$TMP_ROOT/sleeps"; }
for STUB_FAIL_TEXT in 'gh: API rate limit exceeded for installation. (HTTP 403)' 'gh: You have exceeded a secondary rate limit. (HTTP 403)'; do
  export STUB_FAIL_TEXT
  expect "a rate-limited label read fails closed after one call ($STUB_FAIL_TEXT)" 1 1 "enhancement" 1 \
    "::error::could not read the labels of #6419" "waiting"
  if [[ "$(sleeps)" == "5 10" ]]; then
    ok "a guessed stop is not waited for, and the retries make no call"
  else
    fail "a guessed stop slept '$(sleeps)', not the caller's '5 10'"
  fi
done
export STUB_FAIL_TEXT='gh: Resource not accessible by integration (HTTP 403)'
expect "a 403 that is not a rate limit fails closed without a wait" 1 3 "" 3 "::error::could not read the labels of #6419" "rate limited"
if [[ "$(sleeps)" == "5 10" ]]; then
  ok "a 403 that is not a rate limit keeps the caller's retries only"
else
  fail "a 403 that is not a rate limit slept '$(sleeps)'"
fi
unset STUB_FAIL_TEXT
expect "an unreadable label list fails closed" 1 3 "" 3 "::error::could not read the labels of #6419"
if grep -q '^held=' "$TMP_ROOT/output"; then
  fail "an unreadable label list output held"
else
  ok "an unreadable label list outputs no held"
fi

export STUB_TRACKER="$CUSTOM"
expect "the base tracker's human-gated label holds" 1 1 "owner-call" 0 "::error::#6419 carries 'owner-call'. $APPROVE"
if grep -qxF 'label=owner-call' "$TMP_ROOT/output"; then
  ok "the output names the base tracker's label"
else
  fail "the output does not name the base tracker's label: '$(cat "$TMP_ROOT/output")'"
fi
expect "needs-human does not hold when the tracker names another label" 0 1 "needs-human" 0 "#6419 carries no 'owner-call' label."
export STUB_TRACKER='{not json'
expect "an invalid tracker config fails closed" 1 0 "" 0 "::error::cannot read the human-gated role label"
export STUB_TRACKER="$CUSTOM" STUB_CHECKOUT_FAILED=1
expect "a base checkout that failed fails closed" 1 0 "" 0 "::error::could not read .work-item-tracker.json at $BASE; re-run this run."
unset STUB_TRACKER STUB_CHECKOUT_FAILED
export STUB_TRACKER=''
expect "an empty tracker config falls back to needs-human" 1 1 "needs-human" 0 "carries 'needs-human'"
export STUB_TRACKER='   '
expect "a whitespace-only tracker config fails closed" 1 0 "" 0 "::error::cannot read the human-gated role label"
export STUB_TRACKER='{"config":{"role_labels":{"human-gated":"  owner-call "}}}'
expect "the tracker's label is trimmed" 1 1 "owner-call" 0 "::error::#6419 carries 'owner-call'. $APPROVE"
export STUB_TRACKER='{"config":{"role_labels":{"human-gated":"  "}}}'
expect "a blank tracker label falls back to needs-human" 1 1 "needs-human" 0 "carries 'needs-human'"
# The rule is the base's merge-holds.mjs humanGatedLabel: a base that cannot
# judge fails closed before any read.
export STUB_TRACKER="$CUSTOM" STUB_NO_MODULE=1
expect "a base with no merge-holds.mjs fails closed" 1 0 "" 0 "::error::cannot read the human-gated role label from .work-item-tracker.json at $BASE with its merge-holds.mjs"
unset STUB_NO_MODULE
export STUB_MODULE_TEXT='export const other = 1;'
expect "a base module without humanGatedLabel fails closed" 1 0 "" 0 "::error::cannot read the human-gated role label"
export STUB_MODULE_TEXT='export const humanGatedLabel = () => 7;'
expect "a base module answering no label fails closed" 1 0 "" 0 "::error::cannot read the human-gated role label"
export STUB_MODULE_TEXT='export const humanGatedLabel = () => "";'
expect "a base module answering an empty label fails closed" 1 0 "" 0 "::error::cannot read the human-gated role label"
unset STUB_TRACKER STUB_MODULE_TEXT
export BASE_SHA=main
expect "a base that is not a commit SHA fails closed without a call" 1 0 "" 0 "::error::the base commit 'main' is not a commit SHA"
unset BASE_SHA

test_harness::report
