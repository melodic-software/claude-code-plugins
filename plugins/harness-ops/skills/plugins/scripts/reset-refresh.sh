#!/usr/bin/env bash
# Operator-run reset of the user-scope plugin fleet: move the marketplace
# clones and `cache/` (and, for `clean`, `data/`) aside, re-fetch them through
# the documented CLI, and prove the configuration came back unchanged.
#
# Usage:
#   reset-refresh.sh preview
#   reset-refresh.sh refresh [--journal-root <dir>]
#   reset-refresh.sh clean [--journal-root <dir>]
#
# `preview` changes nothing and calls no CLI: it prints the count and size of
# what `refresh` would move aside (each known marketplace's clone under
# `plugins/marketplaces/`, and `plugins/cache/` with its `temp_git_*` entries)
# and the user-scope ids it would reinstall, then what `clean` would also
# discard (`plugins/data/`) and any earlier `plugins.bak-*` backup.
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
# `clean` does all of that, plus:
#   - Refuses unless stdin is a terminal (it asks before some installs, so it
#     aborts when run autonomously) and while an earlier `~/.claude/plugins.bak-*`
#     exists, so at most one backup is kept.
#   - Moves `cache/`, the clones and `data/` into `~/.claude/plugins.bak-<ts>`
#     instead of the run directory, and never deletes that backup.
#   - Installs with `--json`. When an install only displays a marketplace-declared
#     command, it prints that command and asks; on yes it re-runs with
#     `--accept-command <sha256>`. It never passes `-y`.
#   - Also snapshots every project and local install record, and byte copies of
#     user `settings.json` and each existing project's `.claude/settings.json` and
#     `.claude/settings.local.json`, compared with `cmp`.
#   - On any CLI failure or difference, moves the rebuilt copies into the run
#     directory and the backup back into place, then reports the difference.
#   - On a pass, deletes the run's snapshot files and prints the backup's path
#     and size, the `data/` entries whose setup reruns, the dotfile-managed paths
#     under the plugin root (`chezmoi managed`, when present) and a restart line.
#
# Output: plain text on stdout; every CLI call and its output is appended to
# `<run_dir>/journal.log`, and the snapshots are `<run_dir>/{before,after}.*.json`.
#
# Exit codes:
#   0  preview printed, or refresh or clean finished with every snapshot identical
#   1  refresh or clean finished with a CLI failure or a snapshot difference
#      (clean has moved its backup back)
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
reset-refresh.sh: reset the user-scope plugin fleet with its configuration unchanged.

Usage:
  reset-refresh.sh preview
  reset-refresh.sh refresh [--journal-root <dir>]
  reset-refresh.sh clean [--journal-root <dir>]

Exit: 0 preview, or a run with every snapshot identical; 1 a run with a CLI
failure or a snapshot difference; 2 usage error, refusal or failed move.
EOF
}
die() {
  echo "ERROR: $*" >&2
  exit 2
}
refuse() {
  echo "REFUSED: $*" >&2
  exit 2
}

MODE="${1:-}"
[[ $# -gt 0 ]] && shift
JOURNAL_ROOT="$CLAUDE_DIR/plugins-refresh"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --journal-root)
    [[ $# -ge 2 ]] || die "--journal-root requires a directory"
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
preview | refresh | clean) ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

command -v jq >/dev/null 2>&1 ||
  die "jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)"
for f in "$INSTALLED_JSON" "$MARKETPLACES_JSON" "$USER_SETTINGS"; do
  if [[ ! -f "$f" ]]; then
    [[ "$f" == "$USER_SETTINGS" ]] && continue
    die "not found: $f"
  fi
  # An unreadable file would snapshot as empty before and after and compare equal.
  jq empty "$f" >/dev/null 2>&1 || die "not valid JSON: $f"
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
# Counts the direct entries of directory $1, narrowed by any further find tests.
entry_count() { find "$1" -mindepth 1 -maxdepth 1 "${@:2}" | wc -l | tr -d ' '; }

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
    echo "Cache: $(entry_count "$PLUGINS_DIR/cache") entries, $(entry_count "$PLUGINS_DIR/cache" -name 'temp_git_*') temp_git_* ($(size_kb "$PLUGINS_DIR/cache") KB)"
  else
    echo "Cache: absent"
  fi
  echo "Reinstall at user scope: $(reinstall_ids | grep -c .) id(s)"
  echo "Left out (@builtin): $(user_ids | grep -c '@builtin$') id(s)"
  echo "Project/local records, cache moved but not reinstalled: $(non_user_ids | grep -c .) id(s)"
  if [[ -d "$PLUGINS_DIR/data" ]]; then
    echo "clean also discards data/: $(entry_count "$PLUGINS_DIR/data") entries ($(size_kb "$PLUGINS_DIR/data") KB)"
  else
    echo "clean also discards data/: absent"
  fi
  for bak in "$CLAUDE_DIR"/plugins.bak-*; do
    [[ -e "$bak" ]] && echo "clean refuses while this earlier backup exists: $bak ($(size_kb "$bak") KB)"
  done
  exit 0
fi

# --- refresh and clean ---------------------------------------------------------
[[ -z "${CLAUDE_CODE_REMOTE:-}" ]] ||
  refuse "CLAUDE_CODE_REMOTE is set; run $MODE from a terminal on this machine"
if [[ "$MODE" == "clean" ]]; then
  [[ -t 0 ]] || refuse "clean asks before some installs, so it runs only from a terminal, never autonomously"
  for bak in "$CLAUDE_DIR"/plugins.bak-*; do
    [[ -e "$bak" ]] && refuse "an earlier backup exists: $bak; remove it yourself, then run clean again"
  done
fi
# Git Bash has no pgrep; Windows lists its processes through tasklist.exe. `//` keeps
# MSYS from rewriting the `/FI` switches as paths.
case "$(uname -s 2>/dev/null)" in
MINGW* | MSYS* | CYGWIN*)
  command -v tasklist.exe >/dev/null 2>&1 ||
    refuse "tasklist.exe not found, so no running claude process can be ruled out"
  listing=$(tasklist.exe //FI "IMAGENAME eq claude.exe" //NH //FO CSV) ||
    refuse "tasklist.exe failed, so no running claude process can be ruled out"
  pids=$(printf '%s\n' "$listing" | tr -d '\r' | awk -F'","' '/^"claude\.exe"/ {print $2}')
  ;;
*)
  command -v pgrep >/dev/null 2>&1 ||
    refuse "pgrep not found, so no running claude process can be ruled out"
  pids=$(pgrep -x claude)
  pgrep_rc=$?
  ((pgrep_rc > 1)) &&
    refuse "pgrep failed (exit $pgrep_rc), so no running claude process can be ruled out"
  ;;
esac
[[ -z "$pids" ]] || refuse "a claude process is running (pid ${pids//$'\n'/ }); close every session first"

if [[ -z "${RESET_REFRESH_RUN_DIR:-}" ]]; then
  # Judged on the nearest existing ancestor, so a refused root is never created.
  probe="$JOURNAL_ROOT"
  while [[ ! -d "$probe" ]]; do probe=$(dirname "$probe"); done
  plugins_real=$(cd "$PLUGINS_DIR" && pwd -P)
  probe_real=$(cd "$probe" && pwd -P)
  [[ "$probe_real/" != "$plugins_real"/* ]] ||
    die "the journal root is inside $PLUGINS_DIR; pick a directory outside it"
  mkdir -p "$JOURNAL_ROOT" || exit 2
  root_real=$(cd "$JOURNAL_ROOT" && pwd -P)
  run_dir=$(mktemp -d "$root_real/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX") || exit 2
  cp "${BASH_SOURCE[0]}" "$run_dir/reset-refresh.sh" || exit 2
  RESET_REFRESH_RUN_DIR="$run_dir" exec bash "$run_dir/reset-refresh.sh" "$MODE"
fi
RUN_DIR="$RESET_REFRESH_RUN_DIR"
JOURNAL="$RUN_DIR/journal.log"
: >>"$JOURNAL"
# Out of the caller's directory, which can be inside the cache this run moves.
cd "$RUN_DIR" || exit 2

PARTS="marketplaces installs enabled"
[[ "$MODE" == "clean" ]] && PARTS="$PARTS projects"

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
  [[ "$MODE" == "clean" ]] || return 0
  jqr -S '[.plugins // {} | to_entries[] | .key as $id
    | .value[]? | select(.scope != "user") | {id: $id} + .]
    | sort_by(.id, .scope, .projectPath)' "$INSTALLED_JSON" >"$RUN_DIR/$tag.projects.json"
}

# The settings files clean compares byte for byte: user settings, and the shared
# and local settings of each existing project a project or local record names.
settings_files() {
  [[ -f "$USER_SETTINGS" ]] && echo "$USER_SETTINGS"
  jqr -r '[.plugins // {} | .[][]? | select(.scope != "user") | .projectPath // empty]
    | unique[]' "$INSTALLED_JSON" | while IFS= read -r p; do
    command -v cygpath >/dev/null 2>&1 && p=$(cygpath -u "$p")
    for f in "$p/.claude/settings.json" "$p/.claude/settings.local.json"; do
      [[ -f "$f" ]] && echo "$f"
    done
  done
  return 0
}
snapshot_settings() {
  local i=0 f
  : >"$RUN_DIR/settings.list" || return 1
  while IFS= read -r f; do
    i=$((i + 1))
    cp "$f" "$RUN_DIR/settings.$i" || return 1
    printf '%s\n' "$f" >>"$RUN_DIR/settings.list"
  done < <(settings_files)
}
# Prints each settings file that differs from its copy, or that appeared.
compare_settings() {
  local i=0 f
  while IFS= read -r f; do
    i=$((i + 1))
    cmp -s "$RUN_DIR/settings.$i" "$f" || echo "$f"
  done <"$RUN_DIR/settings.list"
  settings_files | grep -vxF -f "$RUN_DIR/settings.list"
  return 0
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
count_failure() {
  FAILURES=$((FAILURES + 1))
  echo "  failed: claude $* ($(printf '%s' "$CLI_OUT" | tail -n 1))"
}
cli_or_count() {
  if ! run_cli "$@"; then
    case "$CLI_OUT" in
    *"already enabled"* | *"already disabled"*) return 0 ;;
    *) ;;
    esac
    count_failure "$@"
  fi
}
# clean asks before an install that runs a marketplace-declared command, and
# accepts only that command through its sha256, never with -y.
install_user() {
  local id="$1" result sha ans
  if [[ "$MODE" != "clean" ]]; then
    cli_or_count plugin install "$id" --scope user
    return
  fi
  run_cli plugin install "$id" --scope user --json && return 0
  result=$(printf '%s\n' "$CLI_OUT" | tail -n 1)
  sha=$(printf '%s\n' "$result" | jqr -r '.shownCommand.sha256 // empty' 2>/dev/null)
  if [[ -z "$sha" ]]; then
    count_failure plugin install "$id" --scope user --json
    return
  fi
  echo "Installing $id runs a command its marketplace declares:"
  printf '%s\n' "$result" | jqr '.shownCommand'
  read -r -p "Run this command for $id? [y/N] " ans
  case "$ans" in
  y | Y | yes | YES) cli_or_count plugin install "$id" --scope user --json --accept-command "$sha" ;;
  *)
    FAILURES=$((FAILURES + 1))
    echo "  declined: $id is not reinstalled"
    ;;
  esac
}

snapshot before || die "could not snapshot the state files; nothing was moved"
if [[ "$MODE" == "clean" ]] && ! snapshot_settings; then
  die "could not copy the settings files; nothing was moved"
fi
# A read loop, not mapfile: macOS system bash is 3.2.
IDS=()
MPS=()
DATA=()
while IFS= read -r line; do IDS+=("$line"); done < <(reinstall_ids)
while IFS= read -r line; do MPS+=("$line"); done < <(marketplace_names)
if [[ "$MODE" == "clean" && -d "$PLUGINS_DIR/data" ]]; then
  while IFS= read -r line; do DATA+=("$line"); done < <(find "$PLUGINS_DIR/data" -mindepth 1 -maxdepth 1 | sed 's|.*/||' | LC_ALL=C sort)
fi

if [[ "$MODE" == "clean" ]]; then
  # A sibling of plugins/, so each move is a rename on the same filesystem.
  moved="$CLAUDE_DIR/plugins.bak-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir "$moved" "$moved/marketplaces" || die "could not create the backup $moved; nothing was moved"
else
  moved="$RUN_DIR/moved"
  mkdir -p "$moved/marketplaces" || exit 2
fi

# Every target reset so far, whether moved aside or absent before the run.
TARGETS=()
# The rebuilt copies go to the run directory first, so a backup part never
# nests inside its rebuilt namesake, and a target absent before is absent
# again; then the emptied backup is removed.
move_back() {
  local rebuilt="$RUN_DIR/rebuilt" rel ok=1
  mkdir -p "$rebuilt/marketplaces" "$PLUGINS_DIR/marketplaces" || return 1
  for rel in ${TARGETS[@]+"${TARGETS[@]}"}; do
    if [[ -e "$PLUGINS_DIR/$rel" ]] && ! mv "$PLUGINS_DIR/$rel" "$rebuilt/$rel"; then
      ok=0
      echo "  could not move the rebuilt $rel aside"
      continue
    fi
    [[ -e "$moved/$rel" ]] || continue
    mv "$moved/$rel" "$PLUGINS_DIR/$rel" || {
      ok=0
      echo "  could not move $moved/$rel back"
    }
  done
  rmdir "$moved/marketplaces" "$moved" || ok=0
  ((ok))
}
reset_target() {
  if [[ -d "$PLUGINS_DIR/$1" ]] && ! mv "$PLUGINS_DIR/$1" "$moved/$1"; then
    echo "ERROR: could not move $PLUGINS_DIR/$1 aside; nothing was fetched" >&2
    [[ "$MODE" == "clean" ]] && move_back >&2
    exit 2
  fi
  TARGETS+=("$1")
}

reset_target cache
[[ "$MODE" == "clean" ]] && reset_target data
for mp in ${MPS[@]+"${MPS[@]}"}; do
  reset_target "marketplaces/$mp"
done
echo "Moved aside: $moved"

for mp in ${MPS[@]+"${MPS[@]}"}; do
  cli_or_count plugin marketplace update "$mp"
done
for id in ${IDS[@]+"${IDS[@]}"}; do
  install_user "$id"
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
for part in $PARTS; do
  if ! cmp -s "$RUN_DIR/before.$part.json" "$RUN_DIR/after.$part.json"; then
    DIFFS=$((DIFFS + 1))
    echo "  differs: $part (compare $RUN_DIR/before.$part.json and after.$part.json)"
  fi
done
if [[ "$MODE" == "clean" ]]; then
  while IFS= read -r f; do
    DIFFS=$((DIFFS + 1))
    echo "  differs: settings file $f (byte compare against its copy listed in $RUN_DIR/settings.list)"
  done < <(compare_settings)
fi

echo "Marketplaces refreshed: ${#MPS[@]}; ids reinstalled: ${#IDS[@]}; CLI failures: $FAILURES; snapshot differences: $DIFFS"
echo "Run journal: $RUN_DIR"

if [[ "$MODE" == "clean" ]]; then
  if ((FAILURES == 0 && DIFFS == 0)); then
    rm -f "$RUN_DIR"/before.*.json "$RUN_DIR"/after.*.json "$RUN_DIR"/settings.*
    echo "Backup: $moved ($(size_kb "$moved") KB). clean never deletes it and refuses to run"
    echo "again while it exists: remove it yourself once the plugins work."
    echo "Plugins whose setup reruns on first use, their data/ discarded: ${#DATA[@]}"
    for d in ${DATA[@]+"${DATA[@]}"}; do echo "  $d"; done
    if command -v chezmoi >/dev/null 2>&1; then
      echo "Dotfile-managed paths under ~/.claude/plugins (re-apply them with chezmoi apply):"
      managed=$(chezmoi managed --include=files 2>/dev/null | tr -d '\r' | grep '^\.claude/plugins/')
      if [[ -n "$managed" ]]; then printf '%s\n' "$managed" | sed 's|^|  ~/|'; else echo "  none"; fi
    else
      echo "Dotfile-managed paths under ~/.claude/plugins: chezmoi not found, not checked"
    fi
    echo "Restart Claude Code: a session that was open still resolves hooks and skills into the moved tree."
    exit 0
  fi
  echo "Moving the backup back into place"
  if move_back; then
    echo "Moved back: cache/, data/ and the clones are as before the run; the rebuilt copies are in $RUN_DIR/rebuilt."
  else
    echo "MOVE-BACK INCOMPLETE: what is left is in $moved; the rebuilt copies are in $RUN_DIR/rebuilt."
  fi
  ((DIFFS > 0)) && echo "The move-back restores no state or settings file: each difference above is still in place."
  exit 1
fi

echo "The moved-aside copies stay in $moved until you remove them."
((FAILURES == 0 && DIFFS == 0)) && exit 0
echo "To go back: replace $PLUGINS_DIR/cache with $moved/cache, and each"
echo "$PLUGINS_DIR/marketplaces/<name> with $moved/marketplaces/<name>."
exit 1
