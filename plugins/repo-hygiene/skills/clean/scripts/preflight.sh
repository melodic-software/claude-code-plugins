#!/usr/bin/env bash
# Tier-0 pre-flight facts for the clean caches/build/all tiers (detection only).
#
# Output contract:
#   RUNTIME_PROCS: <lines | empty>
#   RECENT_BUILD: <paths | empty>
#   IDE_OPEN: <lines | empty>
#   RUNTIME_PROCS_UNATTRIBUTED: <count | n/a (unscoped)>
#
# RUNTIME_PROCS (Linux/WSL, pgrep + /proc) lists only processes whose cwd or command line
# is at or under a scanned ROOT, as `<pid> <cmd> [repo: <ROOT>]`, at most 5. Matches
# elsewhere on the machine are counted in RUNTIME_PROCS_UNATTRIBUTED (an unreadable cwd
# counts there too). With no /proc (tasklist), RUNTIME_PROCS and IDE_OPEN are
# machine-wide, marked `(unscoped)`.
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

RECENT_BUILD scans each ROOT; with none, the invoking repository. RUNTIME_PROCS keeps only
processes under a ROOT (via /proc); RUNTIME_PROCS_UNATTRIBUTED counts the rest. Without
/proc, RUNTIME_PROCS and IDE_OPEN are machine-wide and marked (unscoped).

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
UNATTRIBUTED="n/a (unscoped)"
RESOLVED_ROOTS=()
for r in "${ROOTS[@]}"; do
  abs="$(cd "$r" 2>/dev/null && pwd -P)" && RESOLVED_ROOTS+=("${abs%/}")
done

# Longest ROOT that $1 (a cwd or command line) is at or under; empty when none.
owner_root() {
  local text="$1" best="" r esc
  for r in "${RESOLVED_ROOTS[@]}"; do
    ((${#r} > ${#best})) || continue
    esc="$(printf '%s' "$r" | sed 's/[][\\.*^$+?(){}|/]/\\&/g')"
    [[ "$text" =~ (^|[^[:alnum:]_./-])${esc}(/|[^[:alnum:]_./-]|$) ]] && best="$r"
  done
  printf '%s' "$best"
}

if command -v pgrep >/dev/null 2>&1 && [[ -d /proc/$$ ]]; then
  skip=" $$ "
  p=$$
  while [[ "$p" =~ ^[0-9]+$ ]] && ((p > 1)); do
    skip+="$p "
    p="$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)"
  done
  scoped=""
  count=0
  unattributed=0
  while read -r pid _; do
    [[ "$pid" =~ ^[0-9]+$ && "$skip" != *" $pid "* ]] || continue
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)"
    cmd="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)"
    cmd="${cmd% }"
    [[ -n "$cmd" ]] || continue
    root="$(owner_root "$cwd ")"
    cmd_root="$(owner_root "$cmd ")"
    ((${#cmd_root} > ${#root})) && root="$cmd_root"
    if [[ -n "$root" ]]; then
      count=$((count + 1))
      ((count > 5)) || scoped+="$pid $cmd [repo: $root]"$'\n'
    else
      unattributed=$((unattributed + 1))
    fi
  done < <(pgrep -af 'dotnet|aspire|node.*mcp-server' 2>/dev/null)
  RUNTIME_PROCS="${scoped%$'\n'}"
  UNATTRIBUTED="$unattributed match(es) outside the scanned repositories"
elif command -v tasklist >/dev/null 2>&1; then
  RUNTIME_PROCS="$(tasklist 2>/dev/null | grep -iE '^(dotnet|aspire|node|devenv|rider64?|fleet)\.exe' | head -5 || true)"
  [[ -z "$RUNTIME_PROCS" ]] || RUNTIME_PROCS+=" (unscoped)"
fi

RECENT_BUILD="$(find "${ROOTS[@]}" -name project.assets.json -mmin "-${RECENT_BUILD_MINUTES}" \
  ! -path "$CLEAN_FIND_EXCLUDE_GIT" 2>/dev/null | head -3 | tr '\n' '; ')"

IDE_OPEN=""
if command -v tasklist >/dev/null 2>&1; then
  IDE_OPEN="$(tasklist 2>/dev/null | grep -iE '^(devenv|rider64?|fleet|webstorm|pycharm)\.exe' | head -5 || true)"
  [[ -z "$IDE_OPEN" ]] || IDE_OPEN+=" (unscoped)"
fi

printf 'RUNTIME_PROCS: %s\n' "${RUNTIME_PROCS:-empty}"
printf 'RECENT_BUILD: %s\n' "${RECENT_BUILD:-empty}"
printf 'IDE_OPEN: %s\n' "${IDE_OPEN:-empty}"
printf 'RUNTIME_PROCS_UNATTRIBUTED: %s\n' "$UNATTRIBUTED"
exit 0
