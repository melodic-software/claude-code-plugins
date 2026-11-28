#!/usr/bin/env bash
# Exit 0 = every hook script is referenced; 1 = one or more unwired;
# 2 = environment / unreadable input (fail closed — never a silent skip).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-hook-wiring-liveness: jq is required but not installed" >&2
  exit 2
fi

SETTINGS=".claude/settings.json"
HOOKS_DIR=".claude/hooks"

if [[ ! -f "$SETTINGS" ]]; then
  echo "check-hook-wiring-liveness: $SETTINGS not found" >&2
  exit 2
fi

if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "check-hook-wiring-liveness: $SETTINGS is not valid JSON" >&2
  exit 2
fi

refs="$(jq -r '
  [
    ((.env // {}) | to_entries[] | .value | strings),
    ((.hooks // {}) | .. | objects | .command | strings),
    ((.hooks // {}) | .. | objects | .args[]? | strings)
  ][]
' "$SETTINGS" | tr -d '\r')"

errors=0
shopt -s nullglob
for hook in "$HOOKS_DIR"/*.sh; do
  base="$(basename "$hook")"
  case "$base" in
  *.test.sh) continue ;;
  *) ;;
  esac
  ere="$(printf '%s' "$base" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
  pat="(^|[/\\\\ \"'])${ere}([/\\\\ \"']|$)"
  wired=0
  while IFS= read -r ref; do
    if [[ -n "$ref" ]] && [[ "$ref" == *"$hook"* || "$ref" =~ $pat ]]; then
      wired=1
      break
    fi
  done <<<"$refs"
  if ((wired)); then
    continue
  fi
  printf 'UNWIRED HOOK: %s is not referenced by %s hook commands or env\n' \
    "$hook" "$SETTINGS" >&2
  errors=$((errors + 1))
done

if ((errors > 0)); then
  cat >&2 <<'REMEDY'

A repo-local hook script under .claude/hooks/ must be wired by
.claude/settings.json (a hook command/args string, or an env value such as
HOOK_TELEMETRY_SINK). An unwired script is dead weight that can still claim
enforcement in its header (#2959: pr-linkage-mcp-gate.sh, stripped in #2188
and never restored). Delete it, or wire it — do not re-add a hook without
ledger evidence (#2188). PR linkage is still reported in CI by the check-contract
step of pr-require-checks.yml's ci-status job, advisory since the contract folded into it.

REMEDY
  exit 1
fi

echo "Every .claude/hooks/*.sh (except *.test.sh) is referenced by .claude/settings.json."
