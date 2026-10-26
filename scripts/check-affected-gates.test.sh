#!/usr/bin/env bash
# Contract test for scripts/check-affected-gates.txt: every hygiene gate the CI
# jobs lint-repo, lint-shell, check-plugins and check-skills feed to the
# aggregator is either run by scripts/check-affected.sh or named there as CI
# only, so the local runner never leaves a gate out silently.
#
#   bash scripts/check-affected-gates.test.sh
#
# The gate set is read from the `<gate>=${{ steps.<id>.outcome }}` rows of each
# job's CHECK_RESULTS block, the feed scripts/check-docs-only-gate.sh and the
# lane-coverage gate already hold to the steps.
# shellcheck disable=SC2016
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2

WORKFLOW="$SELF_DIR/../.github/workflows/pr-require-checks.yml"
GATES="$SELF_DIR/check-affected-gates.txt"
RUNNER="$SELF_DIR/check-affected.sh"

# workflow_gates <workflow>: the gate names the four hygiene jobs feed.
workflow_gates() {
  awk -v jobs='lint-repo lint-shell check-plugins check-skills' '
    BEGIN { n = split(jobs, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
    /^[^ #]/ { injobs = ($0 ~ /^jobs:/); next }
    injobs && /^  [A-Za-z0-9_-]+:[ \t]*$/ { name = $1; sub(/:$/, "", name); on = (name in want); next }
    on && /^ +[a-z0-9-]+=\$\{\{/ { g = $1; sub(/=.*/, "", g); print g }
  ' "$1" | LC_ALL=C sort -u
}

# listed_gates <gates file>: the first column of every row.
listed_gates() {
  awk '!/^[ \t]*(#|$)/ { print $1 }' "$1" | LC_ALL=C sort -u
}

# unlisted <workflow> <gates file>: gates in the workflow with no row.
unlisted() {
  LC_ALL=C comm -23 <(workflow_gates "$1") <(listed_gates "$2")
}

# stale <workflow> <gates file>: rows for a gate the workflow no longer feeds.
stale() {
  LC_ALL=C comm -13 <(workflow_gates "$1") <(listed_gates "$2")
}

# runner_machine_path_excludes <runner>: the ':(exclude)...' pathspecs the
# runner's machine-specific-paths check passes to git grep.
runner_machine_path_excludes() {
  awk -F"'" '/^ +'"'"':\(exclude\)/ { print $2 }' "$1" | LC_ALL=C sort
}

# workflow_machine_path_excludes <workflow>: the pathspecs of the `exclude:`
# input of the workflow's machine-paths step.
workflow_machine_path_excludes() {
  awk '/id: machine_paths$/ { m = 1 } m && /^ +exclude: / { e = 1; next } e { if ($1 ~ /^:\(exclude\)/) print $1; else exit }' "$1" |
    LC_ALL=C sort
}

# workflow_machine_path_extensions <workflow>: an `extensions:` input of the
# machine-paths step, which would override the default the runner scans.
workflow_machine_path_extensions() {
  awk '/id: machine_paths$/ { m = 1; next } m && /^ +- name: / { exit } m && /^ +extensions:/ { print }' "$1"
}

# machine_path_excludes_match <runner> <workflow>: 0 when both name the same
# non-empty set of exclusions.
machine_path_excludes_match() {
  local r w
  r="$(runner_machine_path_excludes "$1")"
  w="$(workflow_machine_path_excludes "$2")"
  [[ -n "$w" && "$r" == "$w" ]]
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

# Each row is `<gate> run <runner check>` or `<gate> ci-only <reason>`.
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

# The typos exclusions in the runner are the `exclude:` input of the workflow's
# typos step.
runner_excludes="$(awk -F"'" "/--exclude '/ { print \$2 }" "$RUNNER" | LC_ALL=C sort)"
workflow_excludes="$(awk '/id: typos$/ { t = 1 } t && /^ +exclude: / { sub(/^ +exclude: /, ""); n = split($0, a, " "); for (i = 1; i <= n; i++) print a[i]; exit }' "$WORKFLOW" | LC_ALL=C sort)"
if [[ -n "$workflow_excludes" && "$runner_excludes" == "$workflow_excludes" ]]; then
  ok "the runner's typos exclusions match the workflow's"
else
  bad "the runner's typos exclusions match the workflow's" "runner: ${runner_excludes//$'\n'/ } workflow: ${workflow_excludes//$'\n'/ }"
fi

# The machine-specific-paths exclusions in the runner are the `exclude:` input
# of the workflow's machine-paths step.
if machine_path_excludes_match "$RUNNER" "$WORKFLOW"; then
  ok "the runner's machine-specific-paths exclusions match the workflow's"
else
  r="$(runner_machine_path_excludes "$RUNNER")"
  w="$(workflow_machine_path_excludes "$WORKFLOW")"
  bad "the runner's machine-specific-paths exclusions match the workflow's" "runner: ${r//$'\n'/ } workflow: ${w//$'\n'/ }"
fi
ext="$(workflow_machine_path_extensions "$WORKFLOW")"
if [[ -z "$ext" ]]; then
  ok "the machine-paths step scans the composite's default extensions, as the runner does"
else
  bad "the machine-paths step scans the composite's default extensions, as the runner does" \
    "the step sets ${ext#"${ext%%[! ]*}"}; set machine_paths_types in scripts/check-affected.sh to match"
fi

# A fixture workflow: a gate added to a hygiene job without a row is found, a
# gate in another job is not, and a row for a removed gate is stale.
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

# A fixture machine-paths step and runner: the same exclusions match, and one
# the runner drops or the workflow adds is a mismatch.
cat >"$tmp/paths-workflow.yml" <<'YAML'
jobs:
  lint-repo:
    steps:
      - name: Check for machine-specific paths
        id: machine_paths
        with:
          # a comment line between the id and the input
          exclude: >-
            :(exclude)a/**
            :(exclude)b.json

      - name: Next step
        with:
          exclude: >-
            :(exclude)not-this-step/**
YAML
printf 'x=(\n  %s\n  %s\n)\n' "':(exclude)b.json'" "':(exclude)a/**'" >"$tmp/runner-same.sh"
printf 'x=(\n  %s\n)\n' "':(exclude)a/**'" >"$tmp/runner-fewer.sh"
if machine_path_excludes_match "$tmp/runner-same.sh" "$tmp/paths-workflow.yml"; then
  ok "the same machine-paths exclusions in the runner and the workflow match"
else
  bad "the same machine-paths exclusions in the runner and the workflow match" \
    "runner: $(runner_machine_path_excludes "$tmp/runner-same.sh") workflow: $(workflow_machine_path_excludes "$tmp/paths-workflow.yml")"
fi
if ! machine_path_excludes_match "$tmp/runner-fewer.sh" "$tmp/paths-workflow.yml"; then
  ok "a machine-paths exclusion the runner lacks is a mismatch"
else
  bad "a machine-paths exclusion the runner lacks is a mismatch" "the runner missing :(exclude)b.json matched"
fi
if [[ -z "$(workflow_machine_path_extensions "$tmp/paths-workflow.yml")" ]]; then
  ok "a machine-paths step without extensions: reports none"
else
  bad "a machine-paths step without extensions: reports none" "got: $(workflow_machine_path_extensions "$tmp/paths-workflow.yml")"
fi
cat >"$tmp/paths-ext.yml" <<'YAML'
jobs:
  lint-repo:
    steps:
      - name: Check for machine-specific paths
        id: machine_paths
        with:
          extensions: "*.md"
YAML
if [[ -n "$(workflow_machine_path_extensions "$tmp/paths-ext.yml")" ]]; then
  ok "a machine-paths step that sets extensions: is reported"
else
  bad "a machine-paths step that sets extensions: is reported" "no extensions: line found in the fixture"
fi

test_harness::report
