#!/usr/bin/env bash
# The lint-repo zizmor gate: every offline audit blocks; the online audits
# block on findings, but a GitHub API network error from them (HTTP 403, 429 or
# 5xx, or no response at all) is a warning naming the status.
#
#   scripts/run-zizmor.sh            (from the repository root; GH_TOKEN set)
#
# Two runs, because one online-audit request error aborts the whole run with
# "no audit was performed", which would hide every offline finding too:
#   1. --no-online-audits: the offline audits. Any non-zero exit fails.
#   2. the full run. Its offline findings are none (run 1 passed), so exit
#      11-14 is an online finding and fails. Exit 1 is "Error during audit";
#      it is downgraded only when zizmor names a GitHub API request error.
# Exit codes and modes, as of 2026-10-18 (recheck on a zizmor bump in
# .github/requirements-ci.txt): https://docs.zizmor.sh/usage/#exit-codes
# and https://docs.zizmor.sh/usage/#operating-modes
set -uo pipefail
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token

config=
if [[ -n "${BASE_SHA:-}" ]]; then
  config=$(mktemp) || exit 2
  git cat-file -e "$BASE_SHA^{commit}" || { echo "::error::The base commit $BASE_SHA is not in the checkout."; exit 2; }
  found=
  for candidate in .github/zizmor.yml .github/zizmor.yaml zizmor.yml zizmor.yaml; do
    if git cat-file -e "$BASE_SHA:$candidate" 2>/dev/null; then
      git show "$BASE_SHA:$candidate" >"$config" || exit 2
      found=$candidate
      break
    fi
  done
  if [[ -z "$found" ]]; then
    gh api -H 'Accept: application/vnd.github.raw' repos/melodic-software/standards/contents/.github/zizmor.yml >"$config" || { echo "::error::melodic-software/standards .github/zizmor.yml could not be read."; exit 2; }
    found=".github/zizmor.yml from melodic-software/standards"
  fi
  echo "zizmor config: $found (not the head's)"
fi

args=(--format=github --persona=regular --color=never ${config:+"--config=$config"})

zizmor "${args[@]}" --no-online-audits -- . || exit

out=$(zizmor "${args[@]}" -- . 2>&1)
rc=$?
printf '%s\n' "$out"
[[ "$rc" -eq 1 && "$out" == *'request error while accessing GitHub API'* ]] || exit "$rc"

status=$(sed -nE 's/.*HTTP status (client|server) error \(([0-9]{3})[^)]*\).*/\2/p' <<<"$out" | head -n 1)
if [[ -n "$status" ]]; then
  [[ "$status" == 403 || "$status" == 429 || "$status" == 5[0-9][0-9] ]] || exit "$rc"
  reason="HTTP $status"
elif [[ "$out" == *'error sending request'* ]]; then
  reason="no HTTP response ($(grep -E '^ +[0-9]+: ' <<<"$out" | tail -n 1 | sed -E 's/^ +[0-9]+: //'))"
else
  exit "$rc"
fi
echo "::warning title=zizmor online audits not run::the GitHub API returned $reason, so zizmor's online audits (known-vulnerable-actions and the others) did not complete on this run; the offline audits passed. Re-run to retry them."
