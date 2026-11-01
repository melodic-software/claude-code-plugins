#!/usr/bin/env bash
# Black-box contract tests for reset-refresh.sh. Each case builds a throwaway
# HOME from fixtures/reset-refresh/ and puts stub `claude`, `pgrep`, `uname` and
# `tasklist.exe` commands first on PATH (STUB_UNAME picks the platform). The committed fixtures are only copied, never written.
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
  chmod +x "$stubs/claude" "$stubs/pgrep" "$stubs/uname" "$stubs/tasklist.exe"
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

run_script() {
  local dir="$1"
  shift
  env -u CLAUDE_CODE_REMOTE -u RESET_REFRESH_RUN_DIR -u STUB_PGREP_PID -u STUB_DROP_AUTOUPDATE \
    -u STUB_UNAME -u STUB_TASKLIST_PID \
    HOME="$dir/home" PATH="$dir/stubs:$PATH" STUB_LOG="$dir/claude.log" \
    ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} bash "$SCRIPT" "$@" 2>"$dir/stderr.txt"
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

if ((FAILED > 0)); then
  echo "$FAILED assertion(s) failed" >&2
  exit 1
fi
echo "All reset-refresh tests passed"
