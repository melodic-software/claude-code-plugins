#!/usr/bin/env bash
# Tier-0 pre-flight facts for the clean caches/build/all tiers (detection only).
#
# Output contract:
#   RUNTIME_PROCS: <lines | empty>
#   RECENT_BUILD: <paths | empty>
#   IDE_OPEN: <lines | empty>
#
# Consumer (SKILL §1.5) owns verdict: confirmation gate vs autonomous abort.
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
  preflight.sh [ROOT...]
  preflight.sh --help

RECENT_BUILD scans each ROOT; with none, the invoking repository.

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

# RECENT_BUILD scans the given roots (clean-batch passes its target repos), else
# the invoking repository.
if (($# > 0)); then
  ROOTS=("$@")
else
  REPO_ROOT="$(clean_repo_root)"
  ROOTS=("${REPO_ROOT:-$(pwd)}")
fi

RUNTIME_PROCS=""
if command -v pgrep >/dev/null 2>&1; then
  RUNTIME_PROCS="$(pgrep -af 'dotnet|aspire|node.*mcp-server' 2>/dev/null | head -5 || true)"
fi
if [[ -z "$RUNTIME_PROCS" ]] && command -v tasklist >/dev/null 2>&1; then
  RUNTIME_PROCS="$(tasklist 2>/dev/null | grep -iE '^(dotnet|aspire|node|devenv|rider64?|fleet)\.exe' | head -5 || true)"
fi

RECENT_BUILD="$(find "${ROOTS[@]}" -name project.assets.json -mmin "-${RECENT_BUILD_MINUTES}" \
  ! -path "$CLEAN_FIND_EXCLUDE_GIT" 2>/dev/null | head -3 | tr '\n' '; ')"

IDE_OPEN=""
if command -v tasklist >/dev/null 2>&1; then
  IDE_OPEN="$(tasklist 2>/dev/null | grep -iE '^(devenv|rider64?|fleet|webstorm|pycharm)\.exe' | head -5 || true)"
fi

printf 'RUNTIME_PROCS: %s\n' "${RUNTIME_PROCS:-empty}"
printf 'RECENT_BUILD: %s\n' "${RECENT_BUILD:-empty}"
printf 'IDE_OPEN: %s\n' "${IDE_OPEN:-empty}"
exit 0
