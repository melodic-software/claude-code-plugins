#!/usr/bin/env bash
# Operator-run refresh of the user-scope plugin fleet: move the marketplace
# clones and `cache/` aside, re-fetch them through the documented CLI, and prove
# the configuration came back unchanged.
#
# Usage:
#   reset-refresh.sh preview
#   reset-refresh.sh refresh [--journal-root <dir>]
#
# `preview` changes nothing and calls no CLI: it prints the count and size of
# what `refresh` would move aside (each known marketplace's clone under
# `plugins/marketplaces/`, and `plugins/cache/` with its `temp_git_*` entries)
# and the user-scope ids it would reinstall.
#
# `refresh` keeps installed_plugins.json, known_marketplaces.json and every
# settings file, and never writes any of them itself:
#   1. Refuses when CLAUDE_CODE_REMOTE is set or a process named `claude` runs,
#      since a live session can write the same state files.
#   2. Makes a run directory under the journal root (default
#      `~/.claude/plugins-refresh`, never inside `~/.claude/plugins`), copies
#      this script there and re-executes the copy, because the original can sit
#      in the cache this run moves aside.
#   3. Snapshots the marketplaces (name, full `source`, `autoUpdate`), the
#      user-scope install records (id, scope) and user `enabledPlugins`.
#   4. Moves `cache/` and each known marketplace's clone into the run
#      directory. Nothing is deleted: the operator removes the run directory.
#      Project and local records lose their cache too and are not reinstalled.
#   5. Runs `claude plugin marketplace update <name>` per known marketplace,
#      then `claude plugin install <id> --scope user` per user-scope record,
#      serially. `@builtin` ids are left out.
#   6. Re-applies `enable` or `disable --scope user` to each reinstalled id whose
#      `enabledPlugins` value the install changed: an install on a recorded,
#      disabled id enables it. "already enabled|disabled" counts as success.
#   7. Snapshots again and compares all three; any difference is a failure.
#
# Output: plain text on stdout; every CLI call and its output is appended to
# `<run_dir>/journal.log`, and the snapshots are `<run_dir>/{before,after}.*.json`.
#
# Exit codes:
#   0  preview printed, or refresh finished with every snapshot identical
#   1  refresh finished with a CLI failure or a snapshot difference
#   2  usage error, a refusal, a missing prerequisite or state file, a state file
#      that is not valid JSON, or a failed move

set -uo pipefail

CLAUDE_DIR="$HOME/.claude"
PLUGINS_DIR="$CLAUDE_DIR/plugins"
INSTALLED_JSON="$PLUGINS_DIR/installed_plugins.json"
MARKETPLACES_JSON="$PLUGINS_DIR/known_marketplaces.json"
USER_SETTINGS="$CLAUDE_DIR/settings.json"

usage() {
  cat <<'EOF'
reset-refresh.sh: refresh the user-scope plugin fleet with its configuration unchanged.

Usage:
  reset-refresh.sh preview
  reset-refresh.sh refresh [--journal-root <dir>]

Exit: 0 preview, or refresh with every snapshot identical; 1 refresh with a CLI
failure or a snapshot difference; 2 usage error, refusal or failed move.
EOF
}

MODE="${1:-}"
[[ $# -gt 0 ]] && shift
JOURNAL_ROOT="$CLAUDE_DIR/plugins-refresh"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --journal-root)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --journal-root requires a directory" >&2
      exit 2
    }
    JOURNAL_ROOT="$2"
    shift 2
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done
case "$MODE" in
preview | refresh) ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi
for f in "$INSTALLED_JSON" "$MARKETPLACES_JSON" "$USER_SETTINGS"; do
  [[ -f "$f" || "$f" == "$USER_SETTINGS" ]] || {
    echo "ERROR: not found: $f" >&2
    exit 2
  }
  # An unreadable file would snapshot as empty before and after and compare equal.
  [[ -f "$f" ]] && ! jq empty "$f" >/dev/null 2>&1 && {
    echo "ERROR: not valid JSON: $f" >&2
    exit 2
  }
done

# jq with the `\r` a Windows jq prints stripped, so no id carries it into a CLI call.
jqr() { jq "$@" | tr -d '\r'; }

user_ids() {
  jqr -r '.plugins // {} | to_entries[]
    | select(any(.value[]?; .scope == "user")) | .key' "$INSTALLED_JSON" | sort
}
non_user_ids() {
  jqr -r '.plugins // {} | to_entries[]
    | select(any(.value[]?; .scope != "user")) | .key' "$INSTALLED_JSON"
}
reinstall_ids() { user_ids | grep -v '@builtin$'; }
marketplace_names() { jqr -r 'keys[]' "$MARKETPLACES_JSON"; }
size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1}'; }

if [[ "$MODE" == "preview" ]]; then
  echo "Preview: refresh would move these aside, then fetch them again"
  n=0
  total=0
  while IFS= read -r mp; do
    [[ -d "$PLUGINS_DIR/marketplaces/$mp" ]] || continue
    kb=$(size_kb "$PLUGINS_DIR/marketplaces/$mp")
    echo "  marketplace clone: $mp (${kb:-0} KB)"
    n=$((n + 1))
    total=$((total + ${kb:-0}))
  done < <(marketplace_names)
  echo "Marketplace clones: $n (${total} KB)"
  if [[ -d "$PLUGINS_DIR/cache" ]]; then
    entries=$(find "$PLUGINS_DIR/cache" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
    temps=$(find "$PLUGINS_DIR/cache" -mindepth 1 -maxdepth 1 -name 'temp_git_*' | wc -l | tr -d ' ')
    echo "Cache: $entries entries, $temps temp_git_* ($(size_kb "$PLUGINS_DIR/cache") KB)"
  else
    echo "Cache: absent"
  fi
  echo "Reinstall at user scope: $(reinstall_ids | grep -c .) id(s)"
  echo "Left out (@builtin): $(user_ids | grep -c '@builtin$') id(s)"
  echo "Project/local records, cache moved but not reinstalled: $(non_user_ids | grep -c .) id(s)"
  exit 0
fi

# --- refresh -------------------------------------------------------------------
if [[ -n "${CLAUDE_CODE_REMOTE:-}" ]]; then
  echo "REFUSED: CLAUDE_CODE_REMOTE is set; run refresh from a terminal on this machine" >&2
  exit 2
fi
# Git Bash has no pgrep; Windows lists its processes through tasklist.exe. `//` keeps
# MSYS from rewriting the `/FI` switches as paths.
case "$(uname -s 2>/dev/null)" in
MINGW* | MSYS* | CYGWIN*)
  if ! command -v tasklist.exe >/dev/null 2>&1; then
    echo "REFUSED: tasklist.exe not found, so no running claude process can be ruled out" >&2
    exit 2
  fi
  if ! listing=$(tasklist.exe //FI "IMAGENAME eq claude.exe" //NH //FO CSV); then
    echo "REFUSED: tasklist.exe failed, so no running claude process can be ruled out" >&2
    exit 2
  fi
  pids=$(printf '%s\n' "$listing" | tr -d '\r' | awk -F'","' '/^"claude\.exe"/ {print $2}')
  if [[ -n "$pids" ]]; then
    echo "REFUSED: a claude process is running (pid ${pids//$'\n'/ }); close every session first" >&2
    exit 2
  fi
  ;;
*)
  if ! command -v pgrep >/dev/null 2>&1; then
    echo "REFUSED: pgrep not found, so no running claude process can be ruled out" >&2
    exit 2
  fi
  pids=$(pgrep -x claude)
  pgrep_rc=$?
  if ((pgrep_rc == 0)); then
    echo "REFUSED: a claude process is running (pid ${pids//$'\n'/ }); close every session first" >&2
    exit 2
  elif ((pgrep_rc != 1)); then
    echo "REFUSED: pgrep failed (exit $pgrep_rc), so no running claude process can be ruled out" >&2
    exit 2
  fi
  ;;
esac

if [[ -z "${RESET_REFRESH_RUN_DIR:-}" ]]; then
  # Judged on the nearest existing ancestor, so a refused root is never created.
  probe="$JOURNAL_ROOT"
  while [[ ! -d "$probe" ]]; do probe=$(dirname "$probe"); done
  plugins_real=$(cd "$PLUGINS_DIR" && pwd -P)
  probe_real=$(cd "$probe" && pwd -P)
  case "$probe_real/" in
  "$plugins_real"/*)
    echo "ERROR: the journal root is inside $PLUGINS_DIR; pick a directory outside it" >&2
    exit 2
    ;;
  *) ;;
  esac
  mkdir -p "$JOURNAL_ROOT" || exit 2
  root_real=$(cd "$JOURNAL_ROOT" && pwd -P)
  run_dir=$(mktemp -d "$root_real/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX") || exit 2
  cp "${BASH_SOURCE[0]}" "$run_dir/reset-refresh.sh" || exit 2
  RESET_REFRESH_RUN_DIR="$run_dir" exec bash "$run_dir/reset-refresh.sh" refresh
fi
RUN_DIR="$RESET_REFRESH_RUN_DIR"
JOURNAL="$RUN_DIR/journal.log"
: >>"$JOURNAL"
# Out of the caller's directory, which can be inside the cache this run moves.
cd "$RUN_DIR" || exit 2

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
snapshot() {
  local tag="$1"
  jqr -S '[to_entries[] | {name: .key, source: .value.source, autoUpdate: .value.autoUpdate}]
    | sort_by(.name)' "$MARKETPLACES_JSON" >"$RUN_DIR/$tag.marketplaces.json" || return 1
  jqr -S '[.plugins // {} | to_entries[] | .key as $id
    | .value[]? | select(.scope == "user") | {id: $id, scope}] | sort_by(.id)' \
    "$INSTALLED_JSON" >"$RUN_DIR/$tag.installs.json" || return 1
  if [[ -f "$USER_SETTINGS" ]]; then
    jqr -S '.enabledPlugins // {}' "$USER_SETTINGS" >"$RUN_DIR/$tag.enabled.json" || return 1
  else
    echo '{}' >"$RUN_DIR/$tag.enabled.json"
  fi
}

FAILURES=0
CLI_OUT=""
# The call and its output go to the journal; the CLI's own exit status is kept.
run_cli() {
  echo "\$ claude $*" >>"$JOURNAL"
  CLI_OUT=$(claude "$@" 2>&1 </dev/null)
  local rc=$?
  printf '%s\n' "$CLI_OUT" >>"$JOURNAL"
  return "$rc"
}
cli_or_count() {
  if ! run_cli "$@"; then
    case "$CLI_OUT" in
    *"already enabled"* | *"already disabled"*) return 0 ;;
    *) ;;
    esac
    FAILURES=$((FAILURES + 1))
    echo "  failed: claude $* ($(printf '%s' "$CLI_OUT" | tail -n 1))"
  fi
}

snapshot before || {
  echo "ERROR: could not snapshot the state files; nothing was moved" >&2
  exit 2
}
# A read loop, not mapfile: macOS system bash is 3.2.
IDS=()
MPS=()
while IFS= read -r line; do IDS+=("$line"); done < <(reinstall_ids)
while IFS= read -r line; do MPS+=("$line"); done < <(marketplace_names)

moved="$RUN_DIR/moved"
mkdir -p "$moved/marketplaces" || exit 2
if [[ -d "$PLUGINS_DIR/cache" ]]; then
  mv "$PLUGINS_DIR/cache" "$moved/cache" || {
    echo "ERROR: could not move $PLUGINS_DIR/cache aside; nothing was fetched" >&2
    exit 2
  }
fi
for mp in ${MPS[@]+"${MPS[@]}"}; do
  [[ -d "$PLUGINS_DIR/marketplaces/$mp" ]] || continue
  mv "$PLUGINS_DIR/marketplaces/$mp" "$moved/marketplaces/$mp" || {
    echo "ERROR: could not move the $mp clone aside; nothing was fetched" >&2
    exit 2
  }
done
echo "Moved aside: $moved"

for mp in ${MPS[@]+"${MPS[@]}"}; do
  cli_or_count plugin marketplace update "$mp"
done
for id in ${IDS[@]+"${IDS[@]}"}; do
  cli_or_count plugin install "$id" --scope user
done

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
for id in ${IDS[@]+"${IDS[@]}"}; do
  was=$(jqr -r --arg id "$id" 'if has($id) then .[$id] | tostring else "" end' "$RUN_DIR/before.enabled.json")
  now=""
  [[ -f "$USER_SETTINGS" ]] &&
    now=$(jqr -r --arg id "$id" '.enabledPlugins // {} | if has($id) then .[$id] | tostring else "" end' "$USER_SETTINGS")
  [[ "$was" == "$now" ]] && continue
  case "$was" in
  true) cli_or_count plugin enable "$id" --scope user ;;
  false) cli_or_count plugin disable "$id" --scope user ;;
  *) ;;
  esac
done

DIFFS=0
snapshot after || {
  DIFFS=$((DIFFS + 1))
  echo "  could not snapshot the state files after the run"
}
for part in marketplaces installs enabled; do
  if ! cmp -s "$RUN_DIR/before.$part.json" "$RUN_DIR/after.$part.json"; then
    DIFFS=$((DIFFS + 1))
    echo "  differs: $part (compare $RUN_DIR/before.$part.json and after.$part.json)"
  fi
done

echo "Marketplaces refreshed: ${#MPS[@]}; ids reinstalled: ${#IDS[@]}; CLI failures: $FAILURES; snapshot differences: $DIFFS"
echo "Run journal: $RUN_DIR"
echo "The moved-aside copies stay in $moved until you remove them."
((FAILURES == 0 && DIFFS == 0)) && exit 0
echo "To go back: replace $PLUGINS_DIR/cache with $moved/cache, and each"
echo "$PLUGINS_DIR/marketplaces/<name> with $moved/marketplaces/<name>."
exit 1
