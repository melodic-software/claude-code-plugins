#!/usr/bin/env bash
# Validate every plugin manifest and the marketplace catalog with the Claude Code CLI.
#
# Requires `claude` on PATH (npm install -g @anthropic-ai/claude-code). The
# per-plugin pass catches a bad plugins/<name>/.claude-plugin/plugin.json; the
# --strict repo-root pass validates the catalog manifest itself, where a bad
# marketplace.json entry surfaces (it is not caught by per-plugin validation).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not on PATH" >&2
  exit 2
fi
node scripts/validate-plugin-contracts.mjs || exit 1
node scripts/generate-catalog.mjs --check || exit 1
node scripts/generate-cheatsheet.mjs --check || exit 1
node plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs --check || exit 1

# --- native-overlap registry: generated-view drift + freshness self-check ----
#
# A second plugin-shipped check wired here, same precedent as the autonomy
# generator above. The engine is Python, and this step is bash-only, so the
# interpreter is resolved through the repo's candidate loop rather than a bare
# `python3` call: a zero-length candidate under a WindowsApps path component is
# the Store's App Execution Alias stub, and executing it opens the Microsoft
# Store or hangs instead of running an interpreter (precedent:
# scripts/check-contract-clause-coverage.test.sh).
OVERLAP="plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py"
OVERLAP_FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$OVERLAP")"
if [[ -z "$OVERLAP_FLOOR" ]]; then
  echo "error: could not parse MIN_PYTHON from $OVERLAP" >&2
  exit 2
fi
OVERLAP_PYTHON=""
for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  if "$candidate" -c "import sys; floor = tuple(int(part) for part in '$OVERLAP_FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" 2>/dev/null; then
    OVERLAP_PYTHON="$candidate"
    break
  fi
done
if [[ -z "$OVERLAP_PYTHON" ]]; then
  echo "error: Python ${OVERLAP_FLOOR}+ not found (tried python3, python) — the native-overlap registry checks cannot run" >&2
  exit 2
fi

"$OVERLAP_PYTHON" "$OVERLAP" generate --check || exit 1

# Exit-3 policy, stated here because it is a decision and not an oversight: the
# self-check exits 0 ok / 1 broken / 3 degraded (2 stays argparse's usage
# error). Degraded means the data is stale-but-honest or a comparison was not
# locally decidable — an upstream release the registry does not own, or no
# `claude` on PATH. Neither is a defect this repo can fix by editing the store,
# and a chronically red gate on such a condition trains people to ignore it. So
# broken fails the gate and degraded prints its summary and passes.
"$OVERLAP_PYTHON" "$OVERLAP" self-check
overlap_status=$?
if [[ $overlap_status -eq 1 ]]; then
  echo "Native-overlap registry self-check reported a broken registry." >&2
  exit 1
elif [[ $overlap_status -eq 3 ]]; then
  echo "Native-overlap registry self-check is degraded (stale-but-honest) — passing with the summary above."
elif [[ $overlap_status -ne 0 ]]; then
  echo "error: native-overlap self-check exited $overlap_status (usage or environment error)" >&2
  exit 2
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "error: claude CLI not on PATH (npm install -g @anthropic-ai/claude-code)" >&2
  exit 2
fi

failed=0
for dir in plugins/*/; do
  [[ -d "$dir" ]] || continue
  echo "=== validate ${dir%/} ==="
  claude plugin validate "$dir" || failed=1
done

echo "=== validate --strict (catalog manifest) ==="
claude plugin validate --strict . || failed=1

if [[ $failed -ne 0 ]]; then
  echo "Plugin validation failed." >&2
  exit 1
fi
echo "All plugin manifests and the catalog validated."
