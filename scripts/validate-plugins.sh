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
