#!/usr/bin/env bash
# test-scope: plugins/source-control/*.md plugins/source-control/scripts/babysit-*.sh lib/cdn-pins/sync.mjs lib/merge-hold-labels.json
# test-scope: plugins/source-control/skills/babysit-prs/scripts/*.py plugins/source-control/skills/babysit-prs/scripts/babysit-python.sh plugins/source-control/skills/babysit-prs/scripts/engine-run.sh ruff.toml
# test-scope: plugins/*/hooks/* docs/conventions/source-control.yaml docs/conventions/pr-pipeline.yaml .github/actions/check-kill-switch/check-kill-switch.mjs .github/actions/check-trusted-trigger/check-trusted-trigger.mjs .github/scripts/lib/github-client.mjs .github/scripts/lib/trusted-actors.mjs .github/scripts/pr-merge/carry-run-cache.mjs .github/scripts/pr-merge/head-ref-map.mjs .github/scripts/pr-merge/rotation.mjs .github/scripts/pr-verify/resolve-pr.mjs plugins/source-control/lib/parse-concern-value.sh plugins/source-control/lib/yaml-subset.awk plugins/source-control/skills/babysit-loop/scripts/*.mjs plugins/source-control/skills/babysit-prs/scripts/tests/fixtures/*/*.json plugins/work-items/reference/escalation-marker.md
# test-scope: .github/actions/* .github/scripts/* .github/workflows/* .github/recurring-schedule.json scripts/sync-hold-floor.py
# test-scope: lib/parse-concern-value.sh lib/prerequisites.mjs lib/publish-gate.mjs lib/yaml-subset.awk plugins/evals/skills/plugin-eval/scripts/noise-report.py plugins/evals/skills/plugin-eval/scripts/run-validity.py plugins/evals/skills/plugin-eval/scripts/win-test.py plugins/evals/skills/validate/scripts/validate-cases.py plugins/harness-ops/skills/inventory/scripts/parser_reader.py plugins/performance/scripts/ratchet.py plugins/work-items/scripts/charge-words.json scripts/check-declared-prerequisites.mjs scripts/validate-plugin-contracts.mjs
# test-scope: .github/source-control-settings.json lib/cli-version-check.mjs plugins/formal-verification/lib/config-cascade.mjs plugins/formal-verification/lib/yaml-subset.mjs plugins/formal-verification/scripts/check.mjs plugins/formal-verification/scripts/settings.mjs plugins/source-control/.claude-plugin/plugin.json scripts/check-read-caller-keys.mjs scripts/upstream-drift-vendored-report.sh scripts/credential-legs/* .github/lane-registry.json scripts/sync-credential-legs.mjs
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "$SCRIPT_DIR" || exit 1

PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    PY="$candidate"
    break
  fi
done

if [[ -z "$PY" ]]; then
  echo "SKIP: Python 3.11+ not found"
  exit 0
fi

FAILED=0

if ! bash "$SCRIPT_DIR/engine-run.sh" a; then
  FAILED=1
fi

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
RUN_RUFF="$REPO_ROOT/scripts/run-ruff.sh"
if [[ -f "$RUN_RUFF" ]]; then
  echo "== ruff (CI pin via scripts/run-ruff.sh) =="
  ruff_rc=0
  bash "$RUN_RUFF" check . tests || ruff_rc=$?
  if [[ "$ruff_rc" -eq 127 ]]; then
    echo "SKIP: pinned ruff not available (install uv or the CI pin; lint pass omitted)"
  elif [[ "$ruff_rc" -ne 0 ]]; then
    FAILED=1
  fi
else
  echo "SKIP: scripts/run-ruff.sh not found (lint pass omitted)"
fi

echo "== guarded-wrapper behavior =="
MERGE_WRAPPER="../../../scripts/source-control-babysit-merge"
RESOLVE_WRAPPER="../../../scripts/source-control-babysit-resolve-thread"

check_exit() {
  local label="$1" want="$2"
  shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (want exit $want, got $got)" >&2
    FAILED=1
  fi
}

check_wrapper_refusal() {
  local label="$1"
  shift
  local stderr got
  stderr="$(bash "$MERGE_WRAPPER" "$@" 2>&1 >/dev/null)"
  got=$?
  if [[ "$got" == "2" && "$stderr" == *"is not permitted through the wrapper"* ]]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (want exit 2 + wrapper refusal text, got $got: $stderr)" >&2
    FAILED=1
  fi
}

check_wrapper_refusal "merge wrapper rejects --allow-unpinned-head" \
  "owner/repo#1" --merge --allow-unpinned-head
check_wrapper_refusal "merge wrapper rejects --allow-unpinned-hea (prefix spelling)" \
  "owner/repo#1" --merge --allow-unpinned-hea
check_wrapper_refusal "merge wrapper rejects --allow-unpinned-head=true (=value spelling)" \
  "owner/repo#1" --merge --allow-unpinned-head=true
check_wrapper_refusal "merge wrapper rejects --allow-unpinned=1 (=value prefix spelling)" \
  "owner/repo#1" --merge --allow-unpinned=1
check_wrapper_refusal "merge wrapper rejects --allow-unpinned-hea=1 (=value prefix spelling)" \
  "owner/repo#1" --merge --allow-unpinned-hea=1
check_exit "merge wrapper does not over-refuse --allow-dependency" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners someone-else --allow-dependency
check_exit "merge wrapper does not over-refuse --allow-unprotected" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners someone-else --allow-unprotected
check_exit "merge wrapper does not over-refuse --allowed-owners=owner" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners=someone-else
check_exit "merge wrapper reaches fail-closed CLI (no allowlist)" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1"
check_exit "resolve wrapper reaches fail-closed CLI (no allowlist)" 3 \
  bash "$RESOLVE_WRAPPER" "owner/repo#1"
check_exit "merge wrapper rejects --autopilot-merge-tier without required sets" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners owner --autopilot-merge-tier
failing_gh="$(mktemp -d)" || exit 1
trap 'rm -rf "$failing_gh"' EXIT
printf '#!/usr/bin/env bash\necho "gh: offline in engine.test.sh" >&2\nexit 1\n' >"$failing_gh/gh"
chmod +x "$failing_gh/gh"
check_exit "merge wrapper refuses --unattended --merge when the policy is unreadable" 10 \
  env PATH="$failing_gh:$PATH" bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners owner \
  --unattended --merge --expected-head aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

exit "$FAILED"
