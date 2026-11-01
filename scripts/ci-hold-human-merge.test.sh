#!/usr/bin/env bash
# Runs the `Fail a human-merge hold a listed person has not lifted` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# report-outcome labels a lanes App pull request that a person merges
# `human-merge-hold`. ci-status fails while the label is on, and once
# it is off passes only when the first removal at or after the newest add was
# a `human` of the base commit's trusted-actor list acting directly. It fails
# closed when it cannot tell.
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

NAME='Fail a human-merge hold a listed person has not lifted'
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
# A draft's ci-status passes by design (`Note a draft`), so the step makes no
# read there; the ready_for_review run judges the hold.
if [[ "$step" == *"if: \${{ !cancelled() && github.event_name == 'pull_request' && github.event.pull_request.draft != true }}"* ]]; then
  ok "step runs on every non-draft pull_request run, whatever the human-gated or cost steps found"
else
  fail "step's condition is not the non-draft pull_request event alone"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line step_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$step_line" && "$step_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi

# The stub logs its arguments. A labels read fails when STUB_LABELS_FAIL is
# set, else prints STUB_LABELS; an events read likewise with STUB_EVENTS
# (pages concatenated, as --paginate prints them).
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*/labels*)
  [[ -z "${STUB_LABELS_FAIL:-}" ]] || exit 1
  printf '%s\n' "${STUB_LABELS:-[]}"
  ;;
*/events*)
  [[ -z "${STUB_EVENTS_FAIL:-}" ]] || exit 1
  printf '%s\n' "${STUB_EVENTS:-[]}"
  ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

BASE=89abcdef0123456789abcdef0123456789abcdef
ACTORS='{"version":1,"actors":[{"id":153232337,"login":"kyle-sexton","kind":"human"},{"id":337595936,"login":"melodic-automation-lanes[bot]","kind":"bot"}]}'
# labeled <label> <at> [login] [id]; unlabeled <label> <at> <id> <login>
labeled() { jq -cn --arg l "$1" --arg at "$2" --arg login "${3:-melodic-automation-lanes[bot]}" --argjson id "${4:-337595936}" \
  '{event: "labeled", created_at: $at, label: {name: $l}, actor: {id: $id, login: $login}}'; }
unlabeled() { jq -cn --arg l "$1" --arg at "$2" --argjson id "$3" --arg login "$4" \
  '{event: "unlabeled", created_at: $at, label: {name: $l}, actor: {id: $id, login: $login}}'; }
OPENED="$(labeled human-merge-hold 2026-10-23T10:00:00Z)"
OWNER_LIFT="$(unlabeled human-merge-hold 2026-10-23T11:00:00Z 153232337 kyle-sexton)"
BOT_LIFT="$(unlabeled human-merge-hold 2026-10-23T10:30:00Z 337595936 'melodic-automation-lanes[bot]')"
STRANGER_LIFT="$(unlabeled human-merge-hold 2026-10-23T10:30:00Z 4242 octocat)"

# expect <label> <want-rc> [want-out]; stubs come from the environment.
expect() {
  local label="$1" want_rc="$2" out rc config="$TMP_ROOT/base-config"
  : >"$TMP_ROOT/log"
  rm -rf "$config" "$TMP_ROOT/pr-reads"
  mkdir -p "$config/.github/standards/trusted-actors"
  printf '%s\n' "${STUB_ACTORS-$ACTORS}" >"$config/.github/standards/trusted-actors/trusted-actors.json"
  [[ -z "${STUB_CHECKOUT_FAILED:-}" ]] || config=
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" PR_NUMBER=6419 \
    GITHUB_REPOSITORY=o/r BASE_SHA="${BASE_SHA-$BASE}" \
    BASE_CONFIG="$config" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ -n "${3:-}" && "$out" != *"$3"* ]]; then
    fail "$label: output lacks '$3': '$out'"
  else
    ok "$label"
  fi
}

export STUB_LABELS STUB_EVENTS
STUB_LABELS='[{"name":"bug"}]'
STUB_EVENTS="[$(labeled needs-human 2026-10-23T09:00:00Z 'github-actions[bot]' 41898282)]"
expect "a pull request never labeled human-merge-hold passes" 0 "No human-merge hold on #6419."
STUB_CHECKOUT_FAILED=1 expect "with no hold the actor list is not needed, so a failed base checkout passes" 0 "No human-merge hold on #6419."

# Deleting the hold line or rewriting the Refs line leaves the label on, so the step still fails.
STUB_LABELS='[{"name":"human-merge-hold"}]'
STUB_EVENTS="[$OPENED]"
expect "a pull request carrying the label fails, whatever its body says" 1 \
  "::error::#6419 carries 'human-merge-hold': a person merges it."
STUB_LABELS='[{"name":"Human-Merge-Hold"}]'
expect "the label holds in any case" 1 "carries 'human-merge-hold'"

STUB_LABELS='[]'
STUB_EVENTS="[$OPENED,$OWNER_LIFT]"
expect "a trusted person's removal lifts it" 0 "kyle-sexton, a person on the trusted-actor list, lifted the human-merge hold"
STUB_EVENTS="[$OPENED][$OWNER_LIFT]"
expect "the events are read across pages" 0 "lifted the human-merge hold"
STUB_EVENTS="[$OPENED,$STRANGER_LIFT,$OWNER_LIFT]"
expect "an account off the list removing it fails, whatever a trusted person did after" 1 \
  "::error::octocat removed 'human-merge-hold' from #6419 and is not a person on the trusted-actor list."
STUB_EVENTS="[$OPENED,$BOT_LIFT]"
expect "the lanes App removing its own label fails" 1 "melodic-automation-lanes[bot] removed 'human-merge-hold'"
STUB_EVENTS="[$OPENED,$(jq -c '.performed_via_github_app = {slug: "some-app"}' <<<"$OWNER_LIFT")]"
expect "a removal an App made for a trusted person fails, naming the App" 1 \
  "::error::kyle-sexton removed 'human-merge-hold' from #6419 through the App some-app"
STUB_EVENTS="[$OWNER_LIFT,$OPENED]"
expect "the first removal after the add decides, not the list order" 0 "lifted the human-merge hold"
STUB_EVENTS="[$OPENED]"
expect "a label off with no removal recorded fails closed" 1 \
  "::error::'human-merge-hold' was added to #6419 at 2026-10-23T10:00:00Z, and no removal since then is recorded."
STUB_EVENTS="[$OPENED,$(unlabeled other-label 2026-10-23T11:00:00Z 153232337 kyle-sexton)]"
expect "removing another label does not lift it" 1 "no removal since then is recorded"
STUB_EVENTS="[$OPENED,$OWNER_LIFT,$(labeled human-merge-hold 2026-10-23T12:00:00Z octocat 4242),$(unlabeled human-merge-hold 2026-10-23T12:05:00Z 4242 octocat)]"
expect "any account adding the label back starts a new hold that only a listed person lifts" 1 "octocat removed 'human-merge-hold'"
STUB_EVENTS="[$OPENED,$STRANGER_LIFT,$(labeled human-merge-hold 2026-10-23T12:00:00Z kyle-sexton 153232337),$(unlabeled human-merge-hold 2026-10-23T12:05:00Z 153232337 kyle-sexton)]"
expect "a listed person adding it back and removing it recovers an untrusted lift" 0 "lifted the human-merge hold"

STUB_EVENTS="[$OPENED,$OWNER_LIFT]"
export STUB_ACTORS='{"actors":[{"id":1,"login":"someone","kind":"human"}]}'
expect "a person missing from the base list is not trusted" 1 "kyle-sexton removed 'human-merge-hold'"
export STUB_ACTORS='{not json'
expect "an unreadable trusted-actor list fails closed" 1 "names no person"
unset STUB_ACTORS
STUB_CHECKOUT_FAILED=1 expect "a hold with a failed base checkout fails closed" 1 \
  "::error::could not read the trusted-actor list at $BASE; re-run this run."
BASE_SHA=main expect "a base that is not a commit SHA fails closed" 1 "::error::the base commit 'main' is not a commit SHA"
STUB_LABELS_FAIL=1 expect "an unreadable label list fails closed" 1 "::error::could not read the labels of #6419; re-run this run."
STUB_EVENTS_FAIL=1 expect "an unreadable event list fails closed" 1 "::error::could not read the events of #6419; re-run this run."

test_harness::report
