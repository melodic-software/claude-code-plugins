#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token

candidates=(.github/zizmor.yml .github/zizmor.yaml zizmor.yml zizmor.yaml)
config=$(mktemp) || exit 2
found=
if [[ -n "${BASE_SHA:-}" ]]; then
  git cat-file -e "$BASE_SHA^{commit}" || { echo "::error::The base commit $BASE_SHA is not in the checkout."; exit 2; }
  for candidate in "${candidates[@]}"; do
    if git cat-file -e "$BASE_SHA:$candidate" 2>/dev/null; then
      git show "$BASE_SHA:$candidate" >"$config" || exit 2
      found="$candidate (not the head's)"
      break
    fi
  done
else
  for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" ]] && { config=; found=$candidate; break; }
  done
fi
if [[ -z "$found" && -n "${STANDARDS_DIR:-}" ]]; then
  cp "$STANDARDS_DIR/.github/zizmor.yml" "$config" || { echo "::error::.github/zizmor.yml could not be read from the standards checkout $STANDARDS_DIR."; exit 2; }
  found=".github/zizmor.yml from the melodic-software/standards checkout"
elif [[ -z "$found" ]]; then
  parser="${BASH_SOURCE[0]%/*}/../lib/parse-concern-value.sh"
  settings=docs/conventions/source-control.yaml
  standards=$(bash "$parser" ${BASE_SHA:+--ref "$BASE_SHA"} "$settings" standards_repository)
  [[ "$standards" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "::error::No standards checkout (STANDARDS_DIR) and no standards_repository in $settings${BASE_SHA:+ at $BASE_SHA}."; exit 2; }
  gh api -H 'Accept: application/vnd.github.raw' "repos/$standards/contents/.github/zizmor.yml" >"$config" || { echo "::error::$standards .github/zizmor.yml could not be read."; exit 2; }
  found=".github/zizmor.yml from $standards"
fi
echo "zizmor config: $found"

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
