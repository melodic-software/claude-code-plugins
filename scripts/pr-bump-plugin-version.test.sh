#!/usr/bin/env bash
# pr-bump-plugin-version.yml runs on pull_request, so its own checkout is the
# pull request's code. A job holding `contents: write` loads every local action
# and script from main's checkout in .base, never from that tree, and still runs
# the bump. A path argument checks another copy of the workflow.
# test-scope: .github/workflows/pr-bump-plugin-version.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

workflow="${1:-$ROOT/.github/workflows/pr-bump-plugin-version.yml}"

# One job per record: the job id, a tab, then its lines joined by \x1f.
jobs="$(awk '
  /^jobs:/ { in_jobs = 1; next }
  in_jobs && /^[^ #]/ { in_jobs = 0 }
  in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
    if (id != "") print id "\t" body
    id = $1; sub(/:$/, "", id); body = ""; next
  }
  in_jobs && id != "" { body = body $0 "\037" }
  END { if (id != "") print id "\t" body }
' "$workflow")"

writers=0
while IFS=$'\t' read -r id body; do
  [[ -n "$id" ]] || continue
  lines="${body//$'\037'/$'\n'}"
  grep -Eq '^ +contents: write' <<<"$lines" || continue
  writers=$((writers + 1))
  pr_local="$(grep -E '^ *(- )?uses: \./' <<<"$lines" | grep -Ev 'uses: \./\.base/' || true)"
  if [[ -z "$pr_local" ]]; then
    ok "$id: every local action loads from .base"
  else
    fail "$id holds contents: write and loads a local action from the PR checkout: $pr_local"
  fi
  pr_script="$(grep -E '(bash|sh|node|python3?|source|\.)[[:space:]]+"?(\./)?(scripts|\.github|plugins)/' <<<"$lines" || true)"
  if [[ -z "$pr_script" ]]; then
    ok "$id: runs no script from the PR checkout"
  else
    fail "$id holds contents: write and runs a script from the PR checkout: $pr_script"
  fi
  base_ref="$(awk '/path: \.base$/ { print prev } { prev = $0 }' <<<"$lines")"
  if [[ "$base_ref" =~ ref:\ refs/heads/main$ ]]; then
    ok "$id: .base is main, not a ref the pull request picks"
  else
    fail "$id: the .base checkout does not pin ref: refs/heads/main (line before path: '$base_ref')"
  fi
  if grep -Eq 'bash \.base/scripts/dependabot-plugin-bump\.sh' <<<"$lines"; then
    ok "$id: runs main's bump script"
  else
    fail "$id: does not run .base/scripts/dependabot-plugin-bump.sh"
  fi
done <<<"$jobs"

if ((writers == 0)); then
  fail "no job in $workflow holds contents: write; the bump cannot land"
fi

test_harness::report
