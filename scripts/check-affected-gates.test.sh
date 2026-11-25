#!/usr/bin/env bash
# shellcheck disable=SC2016
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2

WORKFLOW="$SELF_DIR/../.github/workflows/pr-require-checks.yml"
GATES="$SELF_DIR/check-affected-gates.txt"
RUNNER="$SELF_DIR/check-affected.sh"

workflow_gates() {
  awk -v jobs='lint-repo lint-shell check-plugins check-skills' '
    BEGIN { n = split(jobs, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
    /^[^ #]/ { injobs = ($0 ~ /^jobs:/); next }
    injobs && /^  [A-Za-z0-9_-]+:[ \t]*$/ { name = $1; sub(/:$/, "", name); on = (name in want); next }
    on && /^ +[a-z0-9-]+=\$\{\{/ { g = $1; sub(/=.*/, "", g); print g }
  ' "$1" | LC_ALL=C sort -u
}

listed_gates() {
  awk '!/^[ \t]*(#|$)/ { print $1 }' "$1" | LC_ALL=C sort -u
}

unlisted() {
  LC_ALL=C comm -23 <(workflow_gates "$1") <(listed_gates "$2")
}

stale() {
  LC_ALL=C comm -13 <(workflow_gates "$1") <(listed_gates "$2")
}

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT

gates_in_workflow="$(workflow_gates "$WORKFLOW")"
if [[ -n "$gates_in_workflow" ]]; then
  ok "the hygiene jobs' gates are found in the workflow"
else
  bad "the hygiene jobs' gates are found in the workflow" "no <gate>=\${{ ... }} rows parsed from $WORKFLOW"
fi

missing="$(unlisted "$WORKFLOW" "$GATES")"
if [[ -z "$missing" ]]; then
  ok "every hygiene gate is run by the runner or listed CI only"
else
  bad "every hygiene gate is run by the runner or listed CI only" "add a row to scripts/check-affected-gates.txt for: ${missing//$'\n'/ }"
fi

gone="$(stale "$WORKFLOW" "$GATES")"
if [[ -z "$gone" ]]; then
  ok "no row names a gate the workflow stopped feeding"
else
  bad "no row names a gate the workflow stopped feeding" "remove the row for: ${gone//$'\n'/ }"
fi

rows_ok=1
while read -r gate kind rest; do
  case "$kind" in
  run)
    check="${rest%% *}"
    if ! grep -q "^ *run_check $check " "$RUNNER"; then
      bad "row $gate names a check the runner has" "check-affected.sh has no run_check $check"
      rows_ok=0
    fi
    ;;
  ci-only)
    if [[ -z "$rest" ]]; then
      bad "row $gate gives a reason it is CI only" "no reason after ci-only"
      rows_ok=0
    fi
    ;;
  *)
    bad "row $gate is run or ci-only" "kind is '$kind'"
    rows_ok=0
    ;;
  esac
done < <(grep -v '^[[:space:]]*\(#\|$\)' "$GATES")
((rows_ok)) && ok "every row is a runner check or a CI-only gate with a reason"

cat >"$tmp/workflow.yml" <<'YAML'
name: fixture
on:
  pull_request:
jobs:
  lint-repo:
    steps:
      - name: Aggregate
        env:
          CHECK_RESULTS: |
            known-gate=${{ steps.known.outcome }}
            new-gate=${{ steps.new_gate.outcome }}
        run: scripts/aggregate-hygiene-results.sh
  test-bash:
    steps:
      - name: Aggregate
        env:
          CHECK_RESULTS: |
            other-job-gate=${{ steps.other.outcome }}
        run: true
YAML
printf '# gate kind detail\nknown-gate run markdown\nremoved-gate ci-only was removed\n' >"$tmp/gates.txt"
if [[ "$(unlisted "$tmp/workflow.yml" "$tmp/gates.txt")" == new-gate ]]; then
  ok "a gate added to a hygiene job without a row is reported"
else
  bad "a gate added to a hygiene job without a row is reported" "got: $(unlisted "$tmp/workflow.yml" "$tmp/gates.txt")"
fi
if [[ "$(stale "$tmp/workflow.yml" "$tmp/gates.txt")" == removed-gate ]]; then
  ok "a row for a gate the workflow dropped is reported"
else
  bad "a row for a gate the workflow dropped is reported" "got: $(stale "$tmp/workflow.yml" "$tmp/gates.txt")"
fi

test_harness::report
