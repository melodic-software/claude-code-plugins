#!/usr/bin/env bash
# test-scope: plugins/source-control/scripts/* plugins/source-control/skills/babysit-prs/scripts/babysit_*.py plugins/source-control/skills/babysit-prs/scripts/diff_risk.py
# test-scope: plugins/source-control/skills/babysit-prs/scripts/babysit-python.sh plugins/source-control/skills/babysit-prs/scripts/pr_review_threads.py
# test-scope: .github/actions/log-api-budget/rate-limits.json docs/conventions/pr-pipeline.yaml
# test-scope: plugins/source-control/.claude-plugin/plugin.json plugins/source-control/lib/yaml-subset.awk
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 ||
  skip_suite "no python interpreter; the wrappers cannot run"

NO_NET_BIN="$(mktemp -d)"
trap 'rm -rf "$NO_NET_BIN"' EXIT
cat >"$NO_NET_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh must not be invoked by --help\n' >&2
exit 90
STUB
chmod +x "$NO_NET_BIN/gh"

merge_out=$(PATH="$NO_NET_BIN:$PATH" bash "$BIN/source-control-babysit-merge" --help 2>&1)
assert_exit "merge --help exit 0 (canary is a PASS when reachable)" 0 "$?"
assert_contains "merge --help prints usage" "$merge_out" "usage: babysit_merge.py"
assert_not_contains "merge --help never reaches gh" "$merge_out" "gh must not be invoked"
assert_not_contains "merge --help does not reach the fail-closed guard" \
  "$merge_out" '"inScope"'

resolve_out=$(PATH="$NO_NET_BIN:$PATH" bash "$BIN/source-control-babysit-resolve-thread" --help 2>&1)
assert_exit "resolve --help exit 0" 0 "$?"
assert_contains "resolve --help prints usage" "$resolve_out" "usage: babysit_resolve_thread.py"
assert_not_contains "resolve --help never reaches gh" "$resolve_out" "gh must not be invoked"

threads_out=$(PATH="$NO_NET_BIN:$PATH" bash "$BIN/source-control-review-threads" --help 2>&1)
assert_exit "review-threads --help exit 0" 0 "$?"
assert_contains "review-threads --help prints usage" "$threads_out" "usage: pr_review_threads.py"
assert_not_contains "review-threads --help never reaches gh" "$threads_out" "gh must not be invoked"

threads_out=$(PATH="$NO_NET_BIN:$PATH" bash "$BIN/source-control-review-threads" owner/repo#7 2>/dev/null)
assert_exit "review-threads gh failure exits 2" 2 "$?"
assert_contains "review-threads gh failure is UNPROVEN" "$threads_out" "THREADS_UNPROVEN reason=fetch-failed pr=owner/repo#7"

unpinned_out=$(bash "$BIN/source-control-babysit-merge" --help --allow-unpinned-head 2>&1)
assert_exit "unpinned-head refused even alongside --help" 2 "$?"
assert_contains "unpinned-head refusal names the flag" "$unpinned_out" "--allow-unpinned-head"

[[ $FAILED -eq 0 ]] || exit 1
