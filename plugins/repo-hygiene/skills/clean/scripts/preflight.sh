#!/usr/bin/env bash
# Tier-0 pre-flight facts for the clean caches/build/all tiers (detection only).
#
# Output contract:
#   RUNTIME_PROCS: <lines | empty>
#   RECENT_BUILD: <paths | empty>
#   IDE_OPEN: <lines | empty>
#
# Consumer (SKILL §1.5) owns verdict: AskUserQuestion vs autonomous abort.
# Exit: always 0.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh
source "$SCRIPT_DIR/lib/clean-common.sh"
# clean-common.sh re-sources this; preflight reads CLEAN_FIND_EXCLUDE_GIT directly.
# shellcheck source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/cleanup-paths.sh"

RECENT_BUILD_MINUTES=10

usage() {
  cat <<'EOF'
preflight.sh — emit runtime-safety facts for the clean deletion tiers.

Usage:
  preflight.sh
  preflight.sh --help

Exit: always 0.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

REPO_ROOT="$(clean_repo_root)"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

RUNTIME_PROCS=""
if command -v pgrep >/dev/null 2>&1; then
  RUNTIME_PROCS="$(pgrep -af 'dotnet|aspire|node.*mcp-server' 2>/dev/null | head -5 || true)"
fi
if [[ -z "$RUNTIME_PROCS" ]] && command -v tasklist >/dev/null 2>&1; then
  RUNTIME_PROCS="$(tasklist 2>/dev/null | grep -iE '^(dotnet|aspire|node|devenv|rider64?|fleet)\.exe' | head -5 || true)"
fi

RECENT_BUILD="$(find "$REPO_ROOT" -name project.assets.json -mmin "-${RECENT_BUILD_MINUTES}" \
  ! -path "$CLEAN_FIND_EXCLUDE_GIT" 2>/dev/null | head -3 | tr '\n' '; ')"

IDE_OPEN=""
if command -v tasklist >/dev/null 2>&1; then
  IDE_OPEN="$(tasklist 2>/dev/null | grep -iE '^(devenv|rider64?|fleet|webstorm|pycharm)\.exe' | head -5 || true)"
fi

printf 'RUNTIME_PROCS: %s\n' "${RUNTIME_PROCS:-empty}"
printf 'RECENT_BUILD: %s\n' "${RECENT_BUILD:-empty}"
printf 'IDE_OPEN: %s\n' "${IDE_OPEN:-empty}"
exit 0
