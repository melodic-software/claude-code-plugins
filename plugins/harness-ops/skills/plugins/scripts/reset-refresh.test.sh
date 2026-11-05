#!/usr/bin/env bash
# Black-box contract tests for reset-refresh.sh. Each case builds a throwaway
# HOME from fixtures/reset-refresh/ and puts stub `claude`, `pgrep`, `uname`,
# `tasklist.exe` and `chezmoi` commands first on PATH (STUB_UNAME picks the
# platform). `clean` cases run under util-linux `script`, which gives the run the
# terminal clean requires. The committed fixtures are only copied, never written.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/reset-refresh.sh"
FIXTURES="$SCRIPT_DIR/fixtures/reset-refresh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3, got: $2" ;;
  esac
}
same_file() {
  if cmp -s "$2" "$3"; then pass "$1"; else fail "$1" "$3 differs from $2"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# The `claude` stub acts on the case's HOME the way the probed CLI does: an
# install refills the cache and turns a recorded `false` into `true`, enable and
# disable on a plugin already in that state exit 1, and marketplace update
# re-creates a missing clone. STUB_DROP_AUTOUPDATE=1 makes marketplace update
# drop the marketplace's autoUpdate, the difference a refresh must catch.
# STUB_REORDER_SETTINGS=1 makes install reorder settings.json's keys, which only a
# byte compare sees. For STUB_ACCEPT_ID, an install without `--accept-command abc123`
# only displays a marketplace-declared command, as a `--json` failure result.
write_stubs() {
  local stubs="$1"
  mkdir -p "$stubs"
  cat >"$stubs/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
s="$HOME/.claude/settings.json"
p="$HOME/.claude/plugins"
enabled_of() { jq -r --arg id "$1" '.enabledPlugins[$id] | tostring' "$s"; }
set_enabled() {
  jq --arg id "$1" --argjson v "$2" '.enabledPlugins[$id] = $v' "$s" >"$s.next" && mv "$s.next" "$s"
}
case "${1:-} ${2:-}" in
"plugin marketplace")
  mkdir -p "$p/marketplaces/$4"
  if [[ -n "${STUB_DROP_AUTOUPDATE:-}" ]]; then
    jq --arg mp "$4" 'del(.[$mp].autoUpdate)' "$p/known_marketplaces.json" >"$p/km.next" &&
      mv "$p/km.next" "$p/known_marketplaces.json"
  fi
  echo "Successfully updated marketplace: $4"
  ;;
"plugin install")
  id="$3"
  if [[ "$id" == "${STUB_ACCEPT_ID:-}" && "$*" != *"--accept-command abc123"* ]]; then
    printf '{"command":"install","outcome":"failed","message":"command only displayed","shownCommand":{"plugin":"%s","command":"npx setup","sha256":"abc123"}}\n' "$id"
    exit 1
  fi
  if [[ -n "${STUB_REORDER_SETTINGS:-}" ]]; then
    jq '{theme} + .' "$s" >"$s.next" && mv "$s.next" "$s"
  fi
  mkdir -p "$p/cache/${id#*@}/${id%@*}/1.0.0"
  [[ "$(enabled_of "$id")" != "false" ]] || set_enabled "$id" true
  echo "Successfully installed plugin: $id (scope: user)"
  ;;
"plugin enable" | "plugin disable")
  want=true
  [[ "$2" == "disable" ]] && want=false
  if [[ "$(enabled_of "$3")" == "$want" ]]; then
    echo "✘ Failed to $2 plugin \"$3\": already ${2}d at user scope"
    exit 1
  fi
  set_enabled "$3" "$want"
  echo "${2}d $3"
  ;;
*)
  echo "unexpected stub invocation: $*" >&2
  exit 9
  ;;
esac
STUB
  cat >"$stubs/pgrep" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${STUB_PGREP_PID:-}" ]]; then
  echo "$STUB_PGREP_PID"
  exit 0
fi
exit 1
STUB
  cat >"$stubs/uname" <<'STUB'
#!/usr/bin/env bash
echo "${STUB_UNAME:-Linux}"
STUB
  cat >"$stubs/tasklist.exe" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG.tasklist"
if [[ -n "${STUB_TASKLIST_PID:-}" ]]; then
  printf '"claude.exe","%s","Console","1","250,000 K"\r\n' "$STUB_TASKLIST_PID"
else
  printf 'INFO: No tasks are running which match the specified criteria.\r\n'
fi
STUB
  cat >"$stubs/chezmoi" <<'STUB'
#!/usr/bin/env bash
printf '.bashrc\n.claude/plugins/data/alpha-market1/state.txt\n'
STUB
  chmod +x "$stubs/claude" "$stubs/pgrep" "$stubs/uname" "$stubs/tasklist.exe" "$stubs/chezmoi"
}

# CASE_NUM is incremented by the caller: this runs in a subshell.
new_case() {
  local dir="$TEST_TMPDIR/case-$CASE_NUM"
  local plugins="$dir/home/.claude/plugins"
  mkdir -p "$plugins/cache/market1/alpha/0.9.0" "$plugins/cache/temp_git_1a2b3c" \
    "$plugins/marketplaces/market1" "$plugins/marketplaces/market2" \
    "$plugins/marketplaces/orphan" "$plugins/data/alpha-market1" "$dir/journal"
  cp "$FIXTURES/installed_plugins.json" "$FIXTURES/known_marketplaces.json" "$plugins/"
  cp "$FIXTURES/settings.json" "$dir/home/.claude/settings.json"
  printf 'cached\n' >"$plugins/cache/market1/alpha/0.9.0/file.txt"
  printf 'clone\n' >"$plugins/marketplaces/market1/marketplace.json"
  printf 'keep\n' >"$plugins/data/alpha-market1/state.txt"
  write_stubs "$dir/stubs"
  : >"$dir/claude.log"
  echo "$dir"
}

# Sets ENV_CMD to the case's environment: its HOME, the stubs first on PATH, EXTRA_ENV.
env_cmd() {
  ENV_CMD=(env -u CLAUDE_CODE_REMOTE -u RESET_REFRESH_RUN_DIR -u STUB_PGREP_PID -u STUB_DROP_AUTOUPDATE
    -u STUB_UNAME -u STUB_TASKLIST_PID -u STUB_REORDER_SETTINGS -u STUB_ACCEPT_ID
    HOME="$1/home" PATH="$1/stubs:$PATH" STUB_LOG="$1/claude.log" ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"})
}
run_script() {
  local dir="$1"
  shift
  env_cmd "$dir"
  "${ENV_CMD[@]}" bash "$SCRIPT" "$@" 2>"$dir/stderr.txt"
}
# Runs the script on a pseudo-terminal whose input is $2; stdout loses the terminal's `\r`.
run_tty() {
  local dir="$1" input="$2" cmd
  shift 2
  env_cmd "$dir"
  cmd=$(printf '%q ' "${ENV_CMD[@]}" bash "$SCRIPT" "$@")
  printf '%s' "$input" | env SHELL="$BASH" script -qec "$cmd 2>$(printf '%q' "$dir/stderr.txt")" /dev/null | tr -d '\r'
  return "${PIPESTATUS[1]}"
}

tree_state() { (cd "$1" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort); }

# ============================================================================
# Case: preview reports what refresh would move and changes nothing
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
dir=$(new_case)
before=$(tree_state "$dir/home")
EXTRA_ENV=()
out=$(run_script "$dir" preview)
assert_eq "preview: exit 0" "0" "$?"
assert_eq "preview: the HOME tree is unchanged" "$before" "$(tree_state "$dir/home")"
assert_eq "preview: no CLI call" "0" "$(wc -l <"$dir/claude.log" | tr -d ' ')"
assert_contains "preview: counts the known clones only" "$out" "Marketplace clones: 2"
assert_contains "preview: counts temp_git_* in the cache" "$out" "Cache: 2 entries, 1 temp_git_*"
assert_contains "preview: user-scope ids to reinstall" "$out" "Reinstall at user scope: 3 id(s)"
assert_contains "preview: @builtin left out" "$out" "Left out (@builtin): 1 id(s)"
assert_contains "preview: names the project/local records it does not reinstall" "$out" \
  "cache moved but not reinstalled: 2 id(s)"
assert_contains "preview: counts what clean also discards" "$out" "clean also discards data/: 1 entries"
assert_eq "preview: no earlier backup to name" "0" "$(grep -c 'earlier backup' <<<"$out")"

# ============================================================================
# Case: refresh leaves marketplaces, installs and enabledPlugins identical
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
dir=$(new_case)
EXTRA_ENV=()
out=$(run_script "$dir" refresh --journal-root "$dir/journal")
assert_eq "refresh: exit 0" "0" "$?"
assert_contains "refresh: no failure and no difference" "$out" "CLI failures: 0; snapshot differences: 0"
plugins="$dir/home/.claude/plugins"
same_file "refresh: settings.json is byte-identical" "$FIXTURES/settings.json" "$dir/home/.claude/settings.json"
same_file "refresh: installed_plugins.json is unchanged" "$FIXTURES/installed_plugins.json" "$plugins/installed_plugins.json"
same_file "refresh: known_marketplaces.json is unchanged" "$FIXTURES/known_marketplaces.json" "$plugins/known_marketplaces.json"
assert_eq "refresh: each known marketplace is updated" "2" "$(grep -c '^plugin marketplace update ' "$dir/claude.log")"
assert_eq "refresh: each user-scope record is reinstalled at user scope" \
  "plugin install alpha@market1 --scope user|plugin install beta@market1 --scope user|plugin install gamma@market2 --scope user" \
  "$(grep '^plugin install' "$dir/claude.log" | paste -sd '|' -)"
assert_eq "refresh: the disabled id is disabled again" "1" \
  "$(grep -c '^plugin disable beta@market1 --scope user$' "$dir/claude.log")"
assert_eq "refresh: no @builtin or project/local call" "0" "$(grep -c -e '@builtin' -e 'delta@' "$dir/claude.log")"
run_dir=$(find "$dir/journal" -mindepth 1 -maxdepth 1 -type d | head -n 1)
assert_eq "refresh: the run directory holds the copied script" "yes" \
  "$([[ -f "$run_dir/reset-refresh.sh" ]] && echo yes || echo no)"
assert_eq "refresh: the old cache is moved aside, not deleted" "cached" \
  "$(cat "$run_dir/moved/cache/market1/alpha/0.9.0/file.txt" 2>/dev/null)"
assert_eq "refresh: temp_git_* moved with it" "yes" \
  "$([[ -d "$run_dir/moved/cache/temp_git_1a2b3c" ]] && echo yes || echo no)"
assert_eq "refresh: the old clone is moved aside" "clone" \
  "$(cat "$run_dir/moved/marketplaces/market1/marketplace.json" 2>/dev/null)"
assert_eq "refresh: the cache is refilled" "yes" \
  "$([[ -d "$plugins/cache/market1/alpha/1.0.0" && ! -e "$plugins/cache/temp_git_1a2b3c" ]] && echo yes || echo no)"
assert_eq "refresh: an unknown marketplace dir and data/ stay" "yes" \
  "$([[ -d "$plugins/marketplaces/orphan" && -f "$plugins/data/alpha-market1/state.txt" ]] && echo yes || echo no)"

# ============================================================================
# Case: a snapshot difference exits non-zero
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
dir=$(new_case)
EXTRA_ENV=(STUB_DROP_AUTOUPDATE=1)
out=$(run_script "$dir" refresh --journal-root "$dir/journal")
assert_eq "mismatch: exit 1" "1" "$?"
assert_contains "mismatch: names the differing snapshot" "$out" "differs: marketplaces"

# ============================================================================
# Case: refusals act before anything moves
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
dir=$(new_case)
EXTRA_ENV=(CLAUDE_CODE_REMOTE=1)
run_script "$dir" refresh --journal-root "$dir/journal" >/dev/null
assert_eq "CLAUDE_CODE_REMOTE: exit 2" "2" "$?"
assert_contains "CLAUDE_CODE_REMOTE: says why" "$(cat "$dir/stderr.txt")" "REFUSED: CLAUDE_CODE_REMOTE"
assert_eq "CLAUDE_CODE_REMOTE: no CLI call" "0" "$(wc -l <"$dir/claude.log" | tr -d ' ')"
assert_eq "CLAUDE_CODE_REMOTE: the cache stays" "yes" \
  "$([[ -f "$dir/home/.claude/plugins/cache/market1/alpha/0.9.0/file.txt" ]] && echo yes || echo no)"

EXTRA_ENV=(STUB_PGREP_PID=4242)
run_script "$dir" refresh --journal-root "$dir/journal" >/dev/null
assert_eq "running claude: exit 2" "2" "$?"
assert_contains "running claude: names the pid" "$(cat "$dir/stderr.txt")" "pid 4242"

EXTRA_ENV=()
run_script "$dir" refresh --journal-root "$dir/home/.claude/plugins/runs" >/dev/null
assert_eq "journal inside plugins/: exit 2" "2" "$?"
assert_eq "journal inside plugins/: the refused root is not created" "absent" \
  "$([[ -e "$dir/home/.claude/plugins/runs" ]] && echo present || echo absent)"
assert_eq "refusals: nothing was moved or fetched" "0" "$(wc -l <"$dir/claude.log" | tr -d ' ')"

# ============================================================================
# Case: on Git Bash (no pgrep) tasklist.exe decides whether claude.exe runs
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
dir=$(new_case)
EXTRA_ENV=(STUB_UNAME=MINGW64_NT-10.0-26300 STUB_TASKLIST_PID=5150 STUB_PGREP_PID=4242)
run_script "$dir" refresh --journal-root "$dir/journal" >/dev/null
assert_eq "windows running claude.exe: exit 2" "2" "$?"
assert_contains "windows running claude.exe: names the tasklist pid" "$(cat "$dir/stderr.txt")" "pid 5150"
assert_contains "windows: tasklist filters on claude.exe" "$(cat "$dir/claude.log.tasklist")" "IMAGENAME eq claude.exe"
assert_eq "windows running claude.exe: nothing was moved or fetched" "0" "$(wc -l <"$dir/claude.log" | tr -d ' ')"

CASE_NUM=$((CASE_NUM + 1))
dir=$(new_case)
EXTRA_ENV=(STUB_UNAME=MINGW64_NT-10.0-26300 STUB_PGREP_PID=4242)
run_script "$dir" refresh --journal-root "$dir/journal" >/dev/null
assert_eq "windows no claude.exe: refresh runs to exit 0 (pgrep is not consulted)" "0" "$?"

# ============================================================================
# clean: every case below runs on a pseudo-terminal from util-linux `script`
# ============================================================================
if ! script -qec true /dev/null </dev/null >/dev/null 2>&1; then
  echo "SKIP: clean cases need util-linux script for a terminal" >&2
else
  bak_count() { find "$1/home/.claude" -mindepth 1 -maxdepth 1 -name 'plugins.bak-*' | wc -l | tr -d ' '; }
  has() { [[ -e "$1" ]] && echo yes || echo no; }

  # Case: clean discards data/ too, keeps the backup, and reports it
  CASE_NUM=$((CASE_NUM + 1))
  dir=$(new_case)
  EXTRA_ENV=()
  out=$(run_tty "$dir" "" clean --journal-root "$dir/journal")
  assert_eq "clean: exit 0" "0" "$?"
  assert_contains "clean: no failure and no difference" "$out" "CLI failures: 0; snapshot differences: 0"
  plugins="$dir/home/.claude/plugins"
  same_file "clean: settings.json is byte-identical" "$FIXTURES/settings.json" "$dir/home/.claude/settings.json"
  same_file "clean: every project and local record is unchanged" "$FIXTURES/installed_plugins.json" "$plugins/installed_plugins.json"
  same_file "clean: known_marketplaces.json is unchanged" "$FIXTURES/known_marketplaces.json" "$plugins/known_marketplaces.json"
  assert_eq "clean: installs run with --json at user scope" "3" "$(grep -c '^plugin install .* --scope user --json$' "$dir/claude.log")"
  assert_eq "clean: never passes -y" "0" "$(grep -c -e ' -y' -e '--yes' "$dir/claude.log")"
  assert_eq "clean: data/ is discarded" "no" "$(has "$plugins/data")"
  assert_eq "clean: one backup is kept" "1" "$(bak_count "$dir")"
  bak=$(find "$dir/home/.claude" -mindepth 1 -maxdepth 1 -name 'plugins.bak-*' | head -n 1)
  assert_eq "clean: the backup holds data/" "keep" "$(cat "$bak/data/alpha-market1/state.txt" 2>/dev/null)"
  assert_eq "clean: the backup holds the cache and the clone" "cached clone" \
    "$(cat "$bak/cache/market1/alpha/0.9.0/file.txt" "$bak/marketplaces/market1/marketplace.json" 2>/dev/null | paste -sd ' ' -)"
  assert_contains "clean: reports the backup path" "$out" "Backup: $bak ("
  assert_contains "clean: names the plugins whose setup reruns" "$out" "their data/ discarded: 1"
  assert_contains "clean: lists the discarded data/ entry" "$out" "  alpha-market1"
  assert_contains "clean: lists dotfile-managed paths under the plugin root" "$out" "  ~/.claude/plugins/data/alpha-market1/state.txt"
  assert_eq "clean: leaves out managed paths outside the plugin root" "0" "$(grep -c 'bashrc' <<<"$out")"
  assert_contains "clean: says to restart" "$out" "Restart Claude Code"
  run_dir=$(find "$dir/journal" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  assert_eq "clean: a pass deletes the run's snapshot files" "0" \
    "$(find "$run_dir" -maxdepth 1 \( -name 'before.*' -o -name 'after.*' -o -name 'settings.*' \) | wc -l | tr -d ' ')"
  assert_eq "clean: the journal stays" "yes" "$(has "$run_dir/journal.log")"

  # Case: a comparison failure moves the backup back
  CASE_NUM=$((CASE_NUM + 1))
  dir=$(new_case)
  EXTRA_ENV=(STUB_DROP_AUTOUPDATE=1)
  out=$(run_tty "$dir" "" clean --journal-root "$dir/journal")
  assert_eq "clean mismatch: exit 1" "1" "$?"
  assert_contains "clean mismatch: names the differing snapshot" "$out" "differs: marketplaces"
  assert_contains "clean mismatch: says it moved the backup back" "$out" "Moved back:"
  plugins="$dir/home/.claude/plugins"
  assert_eq "move-back: the original cache is back" "cached" "$(cat "$plugins/cache/market1/alpha/0.9.0/file.txt" 2>/dev/null)"
  assert_eq "move-back: the original data/ is back" "keep" "$(cat "$plugins/data/alpha-market1/state.txt" 2>/dev/null)"
  assert_eq "move-back: the original clone is back" "clone" "$(cat "$plugins/marketplaces/market1/marketplace.json" 2>/dev/null)"
  assert_eq "move-back: no rebuilt content stays in plugins/" "no" "$(has "$plugins/cache/market1/alpha/1.0.0")"
  assert_eq "move-back: the emptied backup is gone" "0" "$(bak_count "$dir")"
  run_dir=$(find "$dir/journal" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  assert_eq "move-back: the rebuilt copies are kept in the run directory" "yes" "$(has "$run_dir/rebuilt/cache/market1/alpha/1.0.0")"
  assert_eq "move-back: the snapshots stay for the operator" "yes" "$(has "$run_dir/after.marketplaces.json")"

  # Case: a settings file that differs only in byte order fails the cmp check
  CASE_NUM=$((CASE_NUM + 1))
  dir=$(new_case)
  EXTRA_ENV=(STUB_REORDER_SETTINGS=1)
  out=$(run_tty "$dir" "" clean --journal-root "$dir/journal")
  assert_eq "clean settings cmp: exit 1" "1" "$?"
  assert_contains "clean settings cmp: names the settings file" "$out" "differs: settings file $dir/home/.claude/settings.json"
  assert_eq "clean settings cmp: the sorted enabledPlugins compare passes" "0" "$(grep -c 'differs: enabled' <<<"$out")"
  assert_eq "clean settings cmp: the backup is moved back" "keep" \
    "$(cat "$dir/home/.claude/plugins/data/alpha-market1/state.txt" 2>/dev/null)"

  # Case: an earlier backup refuses the run before anything moves
  CASE_NUM=$((CASE_NUM + 1))
  dir=$(new_case)
  mkdir -p "$dir/home/.claude/plugins.bak-20260101T000000Z"
  printf 'old\n' >"$dir/home/.claude/plugins.bak-20260101T000000Z/marker"
  before=$(tree_state "$dir/home")
  EXTRA_ENV=()
  out=$(run_script "$dir" preview)
  assert_contains "preview: names the earlier backup" "$out" "clean refuses while this earlier backup exists: $dir/home/.claude/plugins.bak-20260101T000000Z"
  run_tty "$dir" "" clean --journal-root "$dir/journal" >/dev/null
  assert_eq "earlier backup: exit 2" "2" "$?"
  assert_contains "earlier backup: says why" "$(cat "$dir/stderr.txt")" "REFUSED: an earlier backup exists"
  assert_eq "earlier backup: no CLI call" "0" "$(wc -l <"$dir/claude.log" | tr -d ' ')"
  assert_eq "earlier backup: the HOME tree is unchanged, the backup included" "$before" "$(tree_state "$dir/home")"

  # Case: clean aborts when run autonomously, with no terminal
  CASE_NUM=$((CASE_NUM + 1))
  dir=$(new_case)
  before=$(tree_state "$dir/home")
  EXTRA_ENV=()
  run_script "$dir" clean --journal-root "$dir/journal" </dev/null >/dev/null
  assert_eq "autonomous: exit 2" "2" "$?"
  assert_contains "autonomous: says why" "$(cat "$dir/stderr.txt")" "never autonomously"
  assert_eq "autonomous: no CLI call" "0" "$(wc -l <"$dir/claude.log" | tr -d ' ')"
  assert_eq "autonomous: the HOME tree is unchanged" "$before" "$(tree_state "$dir/home")"

  # Case: an install that displays a command asks, and a yes accepts it by sha256
  CASE_NUM=$((CASE_NUM + 1))
  dir=$(new_case)
  EXTRA_ENV=(STUB_ACCEPT_ID=alpha@market1)
  out=$(run_tty "$dir" $'y\n' clean --journal-root "$dir/journal")
  assert_eq "accept: exit 0" "0" "$?"
  assert_contains "accept: shows the command" "$out" '"command": "npx setup"'
  assert_contains "accept: asks first" "$(cat "$dir/stderr.txt")" "Run this command for alpha@market1? [y/N]"
  assert_eq "accept: re-runs with --accept-command and the sha256" "1" \
    "$(grep -c '^plugin install alpha@market1 --scope user --json --accept-command abc123$' "$dir/claude.log")"
  assert_eq "accept: never passes -y" "0" "$(grep -c -e ' -y' -e '--yes' "$dir/claude.log")"

  # Case: a no declines the install, which fails the run and moves the backup back
  CASE_NUM=$((CASE_NUM + 1))
  dir=$(new_case)
  EXTRA_ENV=(STUB_ACCEPT_ID=alpha@market1)
  out=$(run_tty "$dir" $'n\n' clean --journal-root "$dir/journal")
  assert_eq "decline: exit 1" "1" "$?"
  assert_contains "decline: says it was declined" "$out" "declined: alpha@market1"
  assert_eq "decline: no --accept-command call" "0" "$(grep -c -e '--accept-command' "$dir/claude.log")"
  assert_eq "decline: the backup is moved back" "keep" \
    "$(cat "$dir/home/.claude/plugins/data/alpha-market1/state.txt" 2>/dev/null)"
fi

if ((FAILED > 0)); then
  echo "$FAILED assertion(s) failed" >&2
  exit 1
fi
echo "All reset-refresh tests passed"
