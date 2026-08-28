#!/usr/bin/env bash
# Gate: every repo-local hook script under .claude/hooks/*.sh (except *.test.sh)
# must be referenced by .claude/settings.json — a hook command (or args string)
# or an env-block value. HOOK_TELEMETRY_SINK is the existing env-wired case.
#
#   scripts/check-hook-wiring-liveness.sh    fail on any unwired hook script
#
# Why: #2959 / #2960. A hook can sit checked-in with a header claiming
# enforcement while settings.json no longer wires it, and nothing notices
# (#2188, #2655). This gate is the wiring-liveness half — it does not restore
# a stripped hook.
#
# Scope: .claude/hooks/*.sh minus *.test.sh. A script whose repo-relative
# path, or whose basename as a bounded path segment, does not appear in
# settings.json hook commands, hook args, or env values fails the gate.
# Scripts outside .claude/hooks/ are out of scope.
#
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

# Env values plus every hook command/args string. Recursive descent on
# .hooks so SessionStart / PreToolUse / exec-form args are all covered.
# CRLF-tolerant: Git Bash can emit \r inside jq string values.
refs="$(jq -r '
  [
    ((.env // {}) | to_entries[] | .value | strings),
    ((.hooks // {}) | .. | objects | .command | strings),
    ((.hooks // {}) | .. | objects | .args[]? | strings)
  ][]
' "$SETTINGS" | tr -d '\r')"

# True when $3 names $1 (repo-relative path) or $2 (basename) as a path
# segment, not as a substring of a longer filename. `gate.sh` must not
# match a ref that only names `not-gate.sh`.
hook_ref_matches() {
  local hook="$1" base="$2" ref="$3" ere pat
  case "$ref" in
  *"$hook"*) return 0 ;;
  *) ;;
  esac
  ere="$(printf '%s' "$base" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
  pat="(^|[/\\\\ \"'])${ere}([/\\\\ \"']|$)"
  [[ "$ref" =~ $pat ]]
}

errors=0
shopt -s nullglob
for hook in "$HOOKS_DIR"/*.sh; do
  base="$(basename "$hook")"
  case "$base" in
  *.test.sh) continue ;;
  *) ;;
  esac
  wired=0
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    # shellcheck disable=SC2310
    hook_ref_matches "$hook" "$base" "$ref" || continue
    wired=1
    break
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
ledger evidence (#2188). Policy enforcement for PR linkage already survives
via the source-control plugin hook plus required CI pr-issue-linkage.

REMEDY
  exit 1
fi

echo "Every .claude/hooks/*.sh (except *.test.sh) is referenced by .claude/settings.json."
