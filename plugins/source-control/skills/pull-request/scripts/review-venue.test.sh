#!/usr/bin/env bash
# Regression tests for review-venue.sh, black-box with a stubbed `gh` on PATH.
# Expected verdicts come from the rule the script header and
# reference/review-venue.md state: healthy only when the newest run with a
# verdict (completed, not skipped or cancelled) succeeded within the window.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/review-venue.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
# The repository's run listing page N comes from $TEST_TMPDIR/page-N.json, a
# lane workflow's runs from $TEST_TMPDIR/wf-<id>.json; a missing file fails.
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEST_TMPDIR/calls"
[[ "\$1" == api ]] || { echo "gh-stub: unrouted \$*" >&2; exit 1; }
case "\$2" in
  */actions/runs\?*)
    page="\${2##*page=}"
    [[ -f "$TEST_TMPDIR/page-\$page.json" ]] || exit 1
    cat "$TEST_TMPDIR/page-\$page.json"
    ;;
  */actions/workflows/*/runs\?*)
    id="\${2#*/actions/workflows/}"; id="\${id%%/*}"
    [[ -f "$TEST_TMPDIR/wf-\$id.json" ]] || exit 1
    cat "$TEST_TMPDIR/wf-\$id.json"
    ;;
  *) echo "gh-stub: unrouted \$*" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

CODE='melodic-software/ci-workflows/.github/workflows/pr-review.yml@a623e29085a3be885718cf9c0c0eca85bb53dd97'
SEC='melodic-software/ci-workflows/.github/workflows/pr-review-security.yml@a623e29085a3be885718cf9c0c0eca85bb53dd97'

# ago <hours> -> an ISO-8601 UTC time that many hours before now
ago() { jq -nr --argjson h "$1" '(now - $h * 3600) | floor | todate'; }

# lane_run <workflow-id> <path> <reusable> -> one run of the repository listing
lane_run() {
  jq -nc --argjson w "$1" --arg p "$2" --arg r "$3" \
    '{id: 1, workflow_id: $w, path: $p, status: "completed", conclusion: "skipped", referenced_workflows: [{path: $r}]}'
}
other_run() { jq -nc '{id: 2, workflow_id: 999, path: ".github/workflows/ci.yml", status: "completed", conclusion: "success"}'; }

# page <n> <run-json>... -> page-n.json
page() {
  local n="$1"
  shift
  jq -sc '{workflow_runs: .}' <<<"$(printf '%s\n' "$@")" >"$TEST_TMPDIR/page-$n.json"
}

# wf <id> <status:conclusion:hours-ago>... -> wf-id.json, newest first
wf() {
  local id="$1" spec runs=()
  shift
  for spec in "$@"; do
    IFS=: read -r st co h <<<"$spec"
    runs+=("$(jq -nc --arg s "$st" --arg c "$co" --arg t "$(ago "$h")" --argjson i "$RANDOM" \
      '{id: $i, status: $s, conclusion: (if $c == "" then null else $c end), created_at: $t}')")
  done
  jq -sc '{workflow_runs: .}' <<<"$(printf '%s\n' "${runs[@]}")" >"$TEST_TMPDIR/wf-$id.json"
}

reset() { rm -f "$TEST_TMPDIR"/page-*.json "$TEST_TMPDIR"/wf-*.json; }

run() {
  : >"$TEST_TMPDIR/calls"
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" "$@"
}

BOTH_PAGE=("$(other_run)" "$(lane_run 11 .github/workflows/pr-review-hosted.yml "$CODE")" "$(lane_run 22 .github/workflows/pr-review-security-hosted.yml "$SEC")")

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:2
wf 22 completed:success:2
out=$(run)
assert_exit "two lanes whose newest run succeeded today exit 0" 0 "$?"
assert_contains "the code lane is covered by CI" "$out" "code-review ci healthy"
assert_contains "the security lane is covered by CI" "$out" "security-review ci healthy"
assert_eq "code-review is reported first" "code-review" "$(head -n1 <<<"$out" | cut -d' ' -f1)"
assert_contains "the line names the caller workflow" "$out" ".github/workflows/pr-review-hosted.yml"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:skipped:1 completed:cancelled:2 in_progress::0 completed:success:3
wf 22 completed:success:3
out=$(run)
assert_contains "skipped, cancelled and running runs carry no verdict" "$out" "code-review ci healthy"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1 completed:success:5
wf 22 completed:success:1
out=$(run)
assert_exit "a failing lane is still a read" 0 "$?"
assert_contains "a lane whose newest verdict failed runs locally" "$out" "code-review local failing"
assert_contains "the failing line names the conclusion" "$out" "concluded failure"
assert_contains "the other lane keeps its own verdict" "$out" "security-review ci healthy"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:timed_out:1
wf 22 completed:startup_failure:1
out=$(run)
assert_contains "a timed-out lane runs locally" "$out" "code-review local failing"
assert_contains "a lane that failed to start runs locally" "$out" "security-review local failing"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:200
wf 22 completed:success:2
out=$(run)
assert_contains "a success older than seven days is stale" "$out" "code-review local stale"
out=$(run --max-age-days 30)
assert_contains "--max-age-days widens the window" "$out" "code-review ci healthy"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:skipped:1 completed:cancelled:1
wf 22 completed:success:1
out=$(run)
assert_contains "a lane with no run carrying a verdict is stale" "$out" "code-review local stale"

reset
page 1 "$(other_run)"
out=$(run)
assert_exit "a repository without lanes is still a read" 0 "$?"
assert_contains "no code lane means a local code review" "$out" "code-review local absent"
assert_contains "no security lane means a local security review" "$out" "security-review local absent"
assert_not_contains "no lane's workflow is read when none was found" "$(cat "$TEST_TMPDIR/calls")" "actions/workflows/"

reset
page 1 "$(other_run)" "$(lane_run 11 .github/workflows/pr-review-hosted.yml "$CODE")"
wf 11 completed:success:1
out=$(run)
assert_contains "a code lane alone is covered" "$out" "code-review ci healthy"
assert_contains "the missing security lane runs locally" "$out" "security-review local absent"

reset
page 1 "$(other_run)" "$(lane_run 11 .github/workflows/pr-review.yml 'someone-else/ci-workflows/.github/workflows/pr-review.yml@main')"
out=$(run)
assert_contains "a review workflow from another owner is not a lane" "$out" "code-review local absent"

reset
full=()
for _ in $(seq 100); do full+=("$(other_run)"); done
page 1 "${full[@]}"
page 2 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
wf 22 completed:success:1
out=$(run)
assert_contains "a lane first seen on page 2 is found" "$out" "code-review ci healthy"
assert_contains "page 2 is requested after a full page 1" "$(cat "$TEST_TMPDIR/calls")" "page=2"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
wf 22 completed:success:1
run --repo acme/app >/dev/null
assert_contains "--repo reaches gh" "$(cat "$TEST_TMPDIR/calls")" "repos/acme/app/actions/runs"
assert_not_contains "both lanes on page 1 stop the scan" "$(cat "$TEST_TMPDIR/calls")" "page=2"

reset
run >/dev/null 2>&1
assert_exit "an unreadable run listing fails closed" 2 "$?"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
run >/dev/null 2>&1
assert_exit "an unreadable lane workflow fails closed" 2 "$?"

reset
echo 'not json' >"$TEST_TMPDIR/page-1.json"
run >/dev/null 2>&1
assert_exit "an unparseable run listing fails closed" 2 "$?"

run --repo 'acme app' >/dev/null 2>&1
assert_exit "a malformed --repo exits 1" 1 "$?"
run --max-age-days 0 >/dev/null 2>&1
assert_exit "a zero-day window exits 1" 1 "$?"
run --pr 7 >/dev/null 2>&1
assert_exit "an unknown flag exits 1" 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
