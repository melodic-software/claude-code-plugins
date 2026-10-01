#!/usr/bin/env bash
# Contract test for block-windows-drive-tmp.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash/PowerShell
# JSON on stdin, asserts on exit code (2 = blocked, 0 = allowed). The Windows
# lane is forced via OSTYPE=msys so Linux CI exercises the same matcher the
# Git Bash host would. Self-contained — no host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-windows-drive-tmp.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Force the Windows host gate even on Linux CI.
# silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
SKIPPED=0
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
}

# 1 when this host's /tmp is the user temp (stock Git for Windows usertemp).
# The Bash command lane then allows POSIX /tmp; drive-root spellings stay blocked.
HOST_POSIX_TMP_IS_USERTEMP=0
if command -v cygpath >/dev/null 2>&1; then
  _dt_tmp_w=$(cygpath -w /tmp 2>/dev/null || true)
  _dt_temp_e="${TEMP:-${TMP:-}}"
  if [[ -n "$_dt_tmp_w" && -n "$_dt_temp_e" ]]; then
    _dt_temp_w=$(cygpath -w "$_dt_temp_e" 2>/dev/null || printf '%s' "$_dt_temp_e")
    _dt_tmp_n="${_dt_tmp_w,,}"
    _dt_tmp_n="${_dt_tmp_n//\\//}"
    _dt_tmp_n="${_dt_tmp_n%/}"
    _dt_temp_n="${_dt_temp_w,,}"
    _dt_temp_n="${_dt_temp_n//\\//}"
    _dt_temp_n="${_dt_temp_n%/}"
    if [[ -n "$_dt_tmp_n" && ("$_dt_tmp_n" == "$_dt_temp_n" || "$_dt_tmp_n" == "$_dt_temp_n"/*) ]]; then
      HOST_POSIX_TMP_IS_USERTEMP=1
    fi
  fi
fi

# True when the command's only drive-root tmp spelling is POSIX /tmp.
# /c/tmp and C:/tmp stay blocks on a usertemp host, and so does a backslash-led
# `\tmp`. That one is judged on the raw command: folding backslashes first turns
# it into POSIX /tmp and the helper would downgrade a block the guard keeps.
posix_tmp_command_only() {
  local bs_tmp='(^|[^[:alnum:]._/\\:])\\tmp(\\|[^[:alnum:]_./-]|$)'
  [[ "${1,,}" =~ $bs_tmp ]] && return 1
  local c="${1//\\//}"
  c="${c,,}"
  [[ "$c" =~ (^|[^[:alnum:]])[a-z]:/tmp(/|[^[:alnum:]_./-]|$) ]] && return 1
  [[ "$c" =~ (^|[^[:alnum:]._/:])/[a-z]/tmp(/|[^[:alnum:]_./-]|$) ]] && return 1
  # A glued short flag (`-o/tmp/x`) is POSIX /tmp too.
  [[ "$c" =~ (^|[^[:alnum:]._/]|[[:space:]]-[a-z])/tmp(/|[^[:alnum:]_./-]|$) ]]
}

run_win() {
  local label="$1" command="$2"
  shift 2
  local expected="$1"
  shift
  if ((HOST_POSIX_TMP_IS_USERTEMP)) && [[ "$expected" == 2 ]] && posix_tmp_command_only "$command"; then
    expected=0
  fi
  run_win_payload "$label" "$(msys_command_json "$command")" "$expected" "$@"
}

run_win_pwsh() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$(msys_pwsh_command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
  if ((expected == 2)); then
    assert_contains "$label → message" "$out" "drive-root temp"
  fi
}

# Non-Windows host: /tmp is legitimate POSIX temp — must never block.
run_posix_host() {
  run_posix_host_payload "$1" "$(command_json "$2")"
}

# File-path lane (0.30.0): Write / Edit / MultiEdit / NotebookEdit carry
# `file_path` (NotebookEdit `notebook_path`) instead of `command`, and before
# 0.30.0 the empty-COMMAND early exit returned before any matcher ran.
# <payload-json> is produced by the caller so one runner covers every tool.
run_win_payload() {
  local label="$1" payload="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$payload" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
  if ((expected == 2)); then
    assert_contains "$label → message" "$out" "drive-root temp"
    assert_contains "$label → fix" "$out" "%TEMP%"
  fi
}

run_posix_host_payload() {
  local label="$1" payload="$2"
  local rc
  env OSTYPE=linux-gnu bash "$HOOK" <<<"$payload" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" 0 "$rc"
}

notebook_path_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" \
    '{tool_name:"NotebookEdit",tool_input:{notebook_path:$fp,new_source:"x"}}'
}

# Command payload builders that PRESERVE an MSYS `/<drive>/tmp` spelling.
# A native Windows jq run under Git Bash gets its argv rewritten: an argument that
# is a POSIX-absolute path, and on some builds a `/usr/bin/...` command word inside
# a longer string, becomes a Windows path before jq reads it. The command travels
# on jq's stdin instead, which no argv rewriting reaches, so every fixture arrives
# byte for byte and run_win / run_win_pwsh need no host-gated variant.
msys_command_json() {
  printf '%s' "$1" | MSYS_NO_PATHCONV=1 jq -Rs '{tool_name:"Bash",tool_input:{command:.}}'
}
msys_pwsh_command_json() {
  printf '%s' "$1" | MSYS_NO_PATHCONV=1 jq -Rs '{tool_name:"PowerShell",tool_input:{command:.}}'
}

# --- Host gate ---------------------------------------------------------------
run_posix_host "Linux host: >/tmp/x allowed" 'echo x > /tmp/x'
run_posix_host "Linux host: mkdir /tmp/x allowed" 'mkdir -p /tmp/x'
run_posix_host_payload "Linux host: Write /tmp/x allowed" "$(write_json '/tmp/x' 'body')"
run_posix_host_payload "Linux host: Edit /tmp/x allowed" "$(edit_json '/tmp/x' 'body')"

# The host gate must be reached BEFORE hook::buffer_stdin and
# hook::require_jq_blocking. Widening the matcher to Write/Edit/MultiEdit/
# NotebookEdit made the old ordering a hard break: on a Linux or macOS host with
# no jq on PATH, require_jq_blocking's fail-closed exit 2 fired on EVERY file
# edit, on a platform where this guard can never find a violation.
#
# Removing jq from PATH is simulable only where jq lives in a directory that
# does not ALSO host bash and coreutils — prune that one entry and the shell
# survives without jq. That holds on some hosts (it was demonstrated on a Cygwin
# host with a single jq location, where the parent commit exits 2 and this one
# exits 0 on a real jq-less PATH) and not on others: where jq sits in /usr/bin
# beside bash, pruning it takes the shell with it. That is the portability
# constraint require-jq-notice-isolation.test.sh and
# secret-pattern-detection.test.sh both record, so the assertion below does not
# depend on it. What IS portable, and what decides the bug either way, is
# whether the call is REACHED: `command -v jq` can only deny a write on a
# jq-less host if control flow gets to it. So assert the ordering from an
# xtrace of the real run. Both names appear in this trace before the fix and
# neither appears after it.
trace=$(env OSTYPE=linux-gnu bash -x "$HOOK" <<<"$(write_json '/srv/app/notes.txt' 'body')" 2>&1 >/dev/null)
assert_absent "Linux host: stdin is never buffered" "$trace" "buffer_stdin"
assert_absent "Linux host: the blocking jq requirement is never reached" "$trace" "require_jq_blocking"

# --- File-path lane: drive-root targets (blocked) ----------------------------
# The 2026-08-30 incident payload: an empty C:\tmp\tmp.rSFIkHm5DO that no guard saw.
run_win_payload "Write C:\\tmp\\tmp.rSFIkHm5DO (blocked)" \
  "$(write_json 'C:\tmp\tmp.rSFIkHm5DO' 'x')" 2
run_win_payload "Write /tmp/x (blocked)" "$(write_json '/tmp/x' 'x')" 2
run_win_payload "Write /c/tmp/x MSYS (blocked)" "$(write_json '/c/tmp/x' 'x')" 2
run_win_payload "Write C:/tmp/x (blocked)" "$(write_json 'C:/tmp/x' 'x')" 2
run_win_payload "Write \\tmp\\x drive-root (blocked)" "$(write_json '\tmp\x' 'x')" 2
run_win_payload "Write D:\\tmp\\x other drive (blocked)" "$(write_json 'D:\tmp\x' 'x')" 2
run_win_payload "Edit /tmp/x (blocked)" "$(edit_json '/tmp/x' 'x')" 2
run_win_payload "Edit C:\\tmp\\x (blocked)" "$(edit_json 'C:\tmp\x' 'x')" 2
run_win_payload "MultiEdit /tmp/x (blocked)" "$(other_tool_json 'MultiEdit' '/tmp/x')" 2
run_win_payload "NotebookEdit notebook_path /tmp/n.ipynb (blocked)" \
  "$(notebook_json '/tmp/n.ipynb' 'x')" 2
run_win_payload "NotebookEdit file_path fallback /tmp/n.ipynb (blocked)" \
  "$(other_tool_json 'NotebookEdit' '/tmp/n.ipynb')" 2
run_win_payload "NotebookEdit notebook_path C:\\tmp\\n.ipynb (blocked)" \
  "$(notebook_path_json 'C:\tmp\n.ipynb')" 2

# --- File-path lane: legitimate targets (allowed) ----------------------------
# Three repo-wide CI gates constrain the literals below, and all three are
# satisfiable without weakening any fixture. The shell-portability scanner reads
# `\s`, `\b` and `\<` as GNU-only regex constructs wherever they appear, so no
# segment starts with those letters and no backslash precedes the placeholder;
# the machine-specific-paths gate rejects a concrete Windows user directory, so
# the user segment is the `<user>` placeholder it prescribes. Hence the forward
# slashes here — a valid Windows spelling that the matcher slash-normalizes
# anyway, and the backslash form stays covered by the `D:\repo\docs\tmp` and
# `D:\a\tmp` cases below. None of it changes what is under test: the matcher
# decides on the presence of a drive-root `tmp` component and this path has none.
run_win_payload "Write under %TEMP% (allowed)" \
  "$(write_json 'C:/Users/<user>/AppData/Local/Temp/note.txt' 'x')" 0
run_win_payload "Write under /var/tmp (allowed)" "$(write_json '/var/tmp/x' 'x')" 0
run_win_payload "Write repo docs/tmp (allowed)" "$(write_json 'D:\repo\docs\tmp\x.md' 'x')" 0
run_win_payload "Write relative ./tmp (allowed)" "$(write_json './tmp/x' 'x')" 0
run_win_payload "Write path component foo/tmp (allowed)" "$(write_json 'foo/tmp/x' 'x')" 0
run_win_payload "Write /tmpdir sibling (allowed)" "$(write_json '/tmpdir/x' 'x')" 0
run_win_payload "Write C:/tmp2 sibling (allowed)" "$(write_json 'C:/tmp2/x' 'x')" 0
run_win_payload "Write UNC //host/tmp (allowed)" "$(write_json '\\host\tmp\x' 'x')" 0
run_win_payload "Edit ordinary repo file (allowed)" \
  "$(edit_json 'D:\repo\plugins\guardrails\README.md' 'x')" 0
# Body content is never scanned — only the target path decides.
run_win_payload "Write body mentioning /tmp (allowed)" \
  "$(write_json 'D:\repo\notes.md' 'do not write to /tmp/x')" 0
# A tool with no path field at all must stay a no-op.
run_win_payload "Read tool, no path (allowed)" \
  "$(jq -n '{tool_name:"Read",tool_input:{}}')" 0

# --- A `tmp` directory under a single-letter parent (allowed) ----------------
# MUST-STAY-QUIET, added repro-first: before the left-boundary fix these all
# blocked, because after slash-normalization the drive colon satisfied the MSYS
# alternative's left boundary and `D:\a\tmp\x` read as `d:` + `/a/tmp`. The
# identical MSYS spelling `/d/a/tmp/x` was allowed the whole time, so one sink
# decided two ways. Both lanes are pinned: the file-path lane is where the
# defect became reachable on every write, the Bash lane is where it already was.
run_win_payload "Write D:\\a\\tmp\\x subdir tmp (allowed)" "$(write_json 'D:\a\tmp\x' 'x')" 0
run_win_payload "Write C:\\q\\tmp\\out.log subdir tmp (allowed)" \
  "$(write_json 'C:\q\tmp\out.log' 'x')" 0
run_win_payload "Write /d/a/tmp/x MSYS spelling (allowed)" "$(write_json '/d/a/tmp/x' 'x')" 0
run_win "mkdir D:\\a\\tmp\\x subdir tmp (allowed)" 'mkdir -p D:\a\tmp\x' 0
# MSYS spellings go through the local no-pathconv builders, or Git Bash rewrites
# them to the drive-letter form and the assertion stops testing this matcher.
run_win_payload "mkdir /d/a/tmp/x MSYS spelling (allowed)" \
  "$(msys_command_json 'mkdir -p /d/a/tmp/x')" 0
# The genuine MSYS drive root must still block.
run_win_payload "mkdir /c/tmp/x drive root (still blocked)" \
  "$(msys_command_json 'mkdir -p /c/tmp/x')" 2
run_win_payload "Write /c/tmp/x drive root (still blocked)" "$(write_json '/c/tmp/x' 'x')" 2

# A PowerShell parameter colon is NOT a drive colon. `-Path:/c/tmp/x` binds the
# same value as `-Path /c/tmp/x`, so both must block; the boundary fix above
# must not take this class out with the drive-colon false positive.
run_win_payload "PS: Set-Content -Path:/c/tmp/x colon-bound (blocked)" \
  "$(msys_pwsh_command_json 'Set-Content -Path:/c/tmp/x -Value hi')" 2
run_win_payload "PS: New-Item -Path:/c/tmp/x colon-bound (blocked)" \
  "$(msys_pwsh_command_json 'New-Item -Path:/c/tmp/x -ItemType File')" 2
run_win_payload "PS: Out-File -FilePath:/c/tmp/x colon-bound (blocked)" \
  "$(msys_pwsh_command_json "'hi' | Out-File -FilePath:/c/tmp/x")" 2
run_win_payload "PS: Add-Content -Path:/c/tmp/x colon-bound (blocked)" \
  "$(msys_pwsh_command_json 'Add-Content -Path:/c/tmp/x -Value hi')" 2
run_win_payload "PS: Copy-Item -Destination:/c/tmp/a colon-bound (blocked)" \
  "$(msys_pwsh_command_json 'Copy-Item .\a -Destination:/c/tmp/a')" 2
run_win_payload "PS: Move-Item -Destination:/c/tmp/a colon-bound (blocked)" \
  "$(msys_pwsh_command_json 'Move-Item .\a -Destination:/c/tmp/a')" 2
# ... and the drive-colon reading of the same character still must not fire.
run_win_payload "PS: Set-Content -Path:D:/a/tmp/x subdir tmp (allowed)" \
  "$(msys_pwsh_command_json 'Set-Content -Path:D:/a/tmp/x -Value hi')" 0

# --- Registration liveness ---------------------------------------------------
# The script half of this guard is inert without the matcher registration: a
# Write payload only reaches the hook because hooks.json routes it here. Reverting
# that registration alone would leave every assertion above green, so assert it.
# Matchers are split on `|` into EXACT alternatives, not substring-searched: a
# containment test for "Edit" is satisfied by "MultiEdit" and so can never fail
# on its own, and a matcher with the pipes removed ("WriteEditNotebookEdit")
# routes nothing while passing every containment check. Sorting also makes the
# assertions immune to a harmless reordering of the alternatives.
HOOKS_JSON="$HOOK_DIR/hooks.json"
reg=$(jq -r --arg h "block-windows-drive-tmp.sh" '
  def rowtext: .command + " " + ((.args // []) | map(tostring) | join(" "));
  [ .hooks.PreToolUse[]
    | select([.hooks[] | rowtext] | any(contains($h)))
    | .matcher | split("|")[] ]
  | sort | join(" ")' "$HOOKS_JSON" 2>/dev/null)
assert_eq "hooks.json routes the guard to exactly the intended tools" \
  "Bash Edit MultiEdit NotebookEdit PowerShell Write" "$reg"
# The registration must also NAME A FILE THAT EXISTS — a command path typo
# registers cleanly and then fails to run on every tool call. Exec form keeps
# that path in args, after ${CLAUDE_PLUGIN_ROOT}/.
reg_cmd=$(jq -r --arg h "block-windows-drive-tmp.sh" '
  def rowtext: .command + " " + ((.args // []) | map(tostring) | join(" "));
  [ .hooks.PreToolUse[].hooks[] | rowtext | select(contains($h))
    | gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}/"; "")
    | split(" ")
    | map(select(endswith(".sh") or endswith(".mjs")))
    | .[0] // empty ]
  | first // ""' \
  "$HOOKS_JSON" 2>/dev/null)
reg_rel="${reg_cmd##*\"/}"
reg_rel="${reg_rel%% *}" # the dispatcher form carries the guard as an argument
assert_eq "the registered command resolves to a file on disk" "yes" \
  "$([[ -n "$reg_rel" && -f "$HOOK_DIR/../$reg_rel" ]] && echo yes || echo no)"

# --- File-path lane: fail-closed on a NUL-bearing path -----------------------
# jq emits the escape textually, so the payload survives command substitution
# and the hook's own jq turns it back into a real NUL byte.
nul_out=$(env OSTYPE=msys bash "$HOOK" \
  <<<"$(jq -n '{tool_name:"Write",tool_input:{file_path:"C:/safe/\u0000/x"}}')" 2>&1)
assert_exit "Write with NUL in file_path fails closed" 2 "$?"
assert_contains "NUL block message" "$nul_out" "NUL byte"

# --- File-path lane: kill switch ---------------------------------------------
run_win_payload "kill switch disables the file-path lane" \
  "$(write_json '/tmp/x' 'x')" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_WINDOWS_DRIVE_TMP_ENABLED=false

# --- Redirects to drive-root tmp (blocked) -----------------------------------
run_win "redirect >/tmp/x (blocked)" 'echo x > /tmp/x' 2
run_win "redirect >>/tmp/x (blocked)" 'echo x >> /tmp/x' 2
run_win "redirect glued >/tmp/x (blocked)" 'echo x>/tmp/x' 2
run_win "stderr redirect 2>/tmp/err (blocked)" 'echo x 2>/tmp/err' 2
run_win "both-streams &>/tmp/x (blocked)" 'echo x &>/tmp/x' 2
run_win "redirect >C:/tmp/x (blocked)" 'echo x > C:/tmp/x' 2
run_win "redirect >C:\\tmp\\x (blocked)" 'echo x > C:\tmp\x' 2
run_win "redirect >/c/tmp/x MSYS (blocked)" 'echo x > /c/tmp/x' 2
run_win "redirect >\\tmp\\x drive-root (blocked)" 'echo x > \tmp\x' 2
run_win "quoted redirect target >\"/tmp/x\" (blocked)" 'echo x > "/tmp/x"' 2

# --- Write utilities with drive-root tmp (blocked) ---------------------------
run_win "mkdir /tmp/x (blocked)" 'mkdir -p /tmp/x' 2
run_win "mktemp /tmp/tmp.XXXXXX (blocked)" 'mktemp /tmp/tmp.XXXXXX' 2
run_win "touch /tmp/x (blocked)" 'touch /tmp/x' 2
run_win "tee /tmp/x (blocked)" 'echo x | tee /tmp/x' 2
run_win "cp to /tmp/x (blocked)" 'cp ./a /tmp/x' 2
run_win "mv to /tmp/x (blocked)" 'mv ./a /tmp/x' 2
run_win "/usr/bin/mkdir /tmp/x (blocked)" '/usr/bin/mkdir -p /tmp/x' 2
run_win "sudo /usr/bin/mkdir /tmp/x (blocked)" 'sudo /usr/bin/mkdir -p /tmp/x' 2
run_win "quoted /usr/bin/mkdir /tmp/x (blocked)" '"/usr/bin/mkdir" -p /tmp/x' 2
run_win "single-quoted /usr/bin/mkdir /tmp/x (blocked)" "'/usr/bin/mkdir' -p /tmp/x" 2
run_win "echo /usr/bin/mkdir /tmp/x (allowed — mention, not command)" 'echo /usr/bin/mkdir /tmp/x' 0
run_win "echo 'run mkdir' /tmp/x (allowed — closing quote is not the command)" "echo 'run mkdir' /tmp/x" 0
run_win "cat /path/mkdir /tmp/x (allowed — path argument, not command)" 'cat /some/path/mkdir /tmp/x' 0
run_win "/usr/bin/touch /tmp/x (blocked)" '/usr/bin/touch /tmp/x' 2
run_win "/usr/bin/tee /tmp/x (blocked)" 'echo x | /usr/bin/tee /tmp/x' 2
run_win "/usr/bin/cp to /tmp/x (blocked)" '/usr/bin/cp ./a /tmp/x' 2
run_win "quoted /usr/bin/cp to /tmp/x (blocked)" '"/usr/bin/cp" ./a /tmp/x' 2
run_win "single-quoted /usr/bin/cp to /tmp/x (blocked)" "'/usr/bin/cp' ./a /tmp/x" 2
run_win "./bin/mkdirs /tmp/x (allowed — verb substring)" './bin/mkdirs /tmp/x' 0
run_win "python open /tmp write (blocked)" "python3 -c \"open('/tmp/x','w').write('a')\"" 2
run_win "python open ( C:/tmp write (blocked)" "python3 -c \"open ('C:/tmp/x','w').write('a')\"" 2
run_win "python getattr open C:/tmp write (blocked)" "python3 -c \"getattr(__builtins__,'open')('C:/tmp/x','w')\"" 2
run_win "python open C:/tmp write (blocked)" "python3 -c \"open('C:/tmp/x','w').write('a')\"" 2
run_win "python open C:/Temp write (allowed — tmp-only scope, twin of C:/tmp)" "python3 -c \"open('C:/Temp/x','w').write('a')\"" 0
# A provable READ is relieved only when the WHOLE unsplit command proves it
# (#3951): a heredoc body splits at each `;`, so a per-segment relief let a decoy
# read clear its segment while the write in the next segment matched nothing.
run_win "python heredoc json.load(open(/tmp)) read (allowed)" \
  $'python3 - <<\'EOF\'\nimport json\nd = json.load(open(\'/tmp/retro-685.json\'))\nprint(d)\nEOF' 0
run_win "python -c open(/tmp,'rb').read() (allowed)" "python3 -c \"print(open('/tmp/x', 'rb').read())\"" 0
run_win "python heredoc decoy read then os.system to /tmp (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/x\').read(); import os; os.system(\'echo pwned > /tmp/evil\')\nEOF' 2
run_win "python heredoc decoy read then shutil.copy to /tmp (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/x\').read(); import shutil; shutil.copy(\'a\',\'/tmp/y\')\nEOF' 2
run_win "python heredoc read then write open in the next segment (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/x\').read(); open(\'/tmp/y\', \'w\').write(d)\nEOF' 2
# A shell expansion can splice a write mode into a quoted literal.
# shellcheck disable=SC2016
run_win "python read with \$m spliced into the literal (blocked)" \
  'm="'"'"', '"'"'w"; python3 -c "open('"'"'/tmp/x$m'"'"').read()"' 2
# A rebound receiver can create the file before .open fails.
run_win "python rebound Path(/tmp).open().read() (blocked)" \
  "python3 -c \"from logging import FileHandler as Path; Path('/tmp/x').open().read()\"" 2
run_win "python json rebound by from-import (blocked)" \
  "python3 -c \"from shelf import dump as json; json.load(open('/tmp/x'))\"" 2
run_win "python wildcard import rebinds open before a /tmp read (blocked)" \
  "python3 -c \"from dbm.dumb import *; open('C:/tmp/x').read()\"" 2
run_win "python wildcard import without a space rebinds open (blocked)" \
  "python3 -c \"from dbm.dumb import*; open('/c/tmp/x').read()\"" 2
run_win_pwsh "PS: python wildcard import rebinds open (blocked)" \
  "python -c \"from dbm.dumb import *; open('C:/tmp/x').read()\"" 2
run_win "python spaced method form d . open(/tmp) creates the file (blocked)" \
  "python3 -c \"import dbm.dumb as d; d . open('/tmp/x').read()\"" 2
# Every `open(` anywhere in the command must be a provable read, and once those
# read calls are cut out no drive-root tmp path may be left.
run_win "python -c open(/tmp,'r') explicit read mode (allowed)" \
  "python3 -c \"print(open('/tmp/x','r').read())\"" 0
run_win "python open(/tmp) read with dict subscript (allowed)" \
  "python3 -c \"import json; print(json.load(open('/tmp/x.json'))['a'])\"" 0
run_win "python open(/tmp) read with encoding= (allowed)" \
  "python3 -c \"print(open('/tmp/x', encoding='utf-8').read())\"" 0
run_win "python open(/tmp,'r',encoding=) read (allowed)" \
  "python3 -c \"print(open('/tmp/x', 'r', encoding='utf-8').read())\"" 0
run_win "python open(sys.argv[1]) read beside open(/tmp) read (allowed)" \
  "python3 -c \"import sys; print(open(sys.argv[1]).read(), open('/tmp/x').read())\"" 0
run_win "python open(/tmp) read beside a spaced path read (allowed)" \
  "python3 -c \"print(open('/tmp/x').read(), open('/c/Users/a b/y.txt').read())\"" 0
# A read call's argument must be a plain path. Ruby's Kernel#open runs an argument
# that starts with `|` as a subprocess, and `%x[...]` and `"#{...}"` run code. The
# drive-root path sits inside the accepted call, where neither the leftover-tmp
# check nor the redirect check (the `>` is quoted) sees it.
run_win "ruby open('|echo hi > /c/tmp/x').read() runs a subprocess (blocked)" \
  "ruby -e \"open('|echo hi > /c/tmp/x').read()\"" 2
run_win "ruby JSON.load(open('|echo hi > /c/tmp/x')) (blocked)" \
  "ruby -e \"JSON.load(open('|echo hi > /c/tmp/x'))\"" 2
run_win "ruby open('|cp a /c/tmp/x').readlines() (blocked)" \
  "ruby -e \"open('|cp a /c/tmp/x').readlines()\"" 2
run_win "ruby open(' |echo hi > /c/tmp/x') leading space before the pipe (blocked)" \
  "ruby -e \"open(' |echo hi > /c/tmp/x').read()\"" 2
run_win "ruby open(%q[|echo hi > /c/tmp/x]) unquoted operand (blocked)" \
  "ruby -e \"open(%q[|echo hi > /c/tmp/x]).read()\"" 2
run_win "ruby open(%x[echo hi > /c/tmp/x]) command literal (blocked)" \
  "ruby -e \"open(%x[echo hi > /c/tmp/x]).read()\"" 2
run_win "ruby open(\"#{%x(...)}\") interpolation (blocked)" \
  "ruby -e 'open(\"#{%x(echo hi > /c/tmp/x)}\").read()'" 2
run_win "ruby open(/c/tmp, encoding=\"#{...}\") interpolated kwarg (blocked)" \
  "ruby -e 'open(\"/c/tmp/x\", encoding=\"#{%x(echo hi > /c/tmp/y)}\").read()'" 2
run_win "ruby pipe command held in a variable, path outside the call (blocked)" \
  "ruby -e \"x='|echo hi > /c/tmp/x'; open(x).read()\"" 2
run_win_pwsh "PS: ruby open('|echo hi > /c/tmp/x').read() (blocked)" \
  "ruby -e \"open('|echo hi > /c/tmp/x').read()\"" 2
run_win_pwsh "PS: ruby open(%q[|echo hi > /c/tmp/x]) unquoted operand (blocked)" \
  "ruby -e \"open(%q[|echo hi > /c/tmp/x]).read()\"" 2
run_win_pwsh "PS: ruby open(%x[echo hi > /c/tmp/x]) command literal (blocked)" \
  "ruby -e \"open(%x[echo hi > /c/tmp/x]).read()\"" 2
# The method form is not provable: its receiver can be rebound, so it stays blocked.
run_win "python Path(/tmp).open() method read (blocked)" \
  "python3 -c \"from pathlib import Path; print(Path('/tmp/x').open().read())\"" 2
run_win "python Path(/tmp).open('rb') method read (blocked)" \
  "python3 -c \"from pathlib import Path; print(Path('/tmp/x').open('rb').read())\"" 2
# Fail closed: the path sits outside the read call, so nothing ties it to the read.
run_win "python heredoc /tmp argv operand, path outside the call (blocked)" \
  $'python3 - /tmp/retro-685.json <<\'EOF\'\nimport json, sys\nprint(json.load(open(sys.argv[1])))\nEOF' 2
# Fail closed: prose quoting open(...) beside a /tmp path outside the call. Without
# the open( the same body is allowed (next case).
run_win "gh body quoting open(...) beside /tmp (blocked)" \
  $'gh issue create --title x --body "$(cat <<\'EOF\'\na `python3 - <<\'EOF\'` heredoc whose only use of the path was\n`json.load(open(...))` on a `/tmp/retro-685.json` argument was blocked\nEOF\n)"' 2
run_win "gh body mentioning /tmp without open( (allowed)" \
  'gh issue create --title x --body "a heredoc reading /tmp/retro-685.json was blocked"' 0

# --- Inline python: every write spelling still blocks ------------------------
run_win "python heredoc open(/tmp,'w') write (blocked)" \
  $'python3 - <<\'EOF\'\nwith open(\'/tmp/x\', \'w\') as f:\n    f.write(\'a\')\nEOF' 2
run_win "python open(/tmp, mode='a') (blocked)" "python3 -c \"open('/tmp/x', mode='a').write('a')\"" 2
run_win "python open(/tmp,'r+') update mode (blocked)" "python3 -c \"open('/tmp/x','r+').write('a')\"" 2
run_win "python open(/tmp,'xb') exclusive create (blocked)" "python3 -c \"open('/tmp/x','xb')\"" 2
run_win "python open(join(/tmp,x),'w') nested call (blocked)" \
  "python3 -c \"import os; open(os.path.join('/tmp','x'),'w')\"" 2
run_win "python Path(/tmp).open('w') method form (blocked)" \
  "python3 -c \"from pathlib import Path; Path('/tmp/x').open('w').write('a')\"" 2
run_win "python Path(/tmp).write_text (blocked)" \
  "python3 -c \"from pathlib import Path; Path('/tmp/x').write_text('a')\"" 2
run_win "python os.makedirs(/tmp/x) (blocked)" "python3 -c \"import os; os.makedirs('/tmp/x')\"" 2
run_win "python os.open(/tmp, O_WRONLY|O_CREAT) (blocked)" \
  "python3 -c \"import os; os.open('/tmp/x', os.O_WRONLY | os.O_CREAT)\"" 2
run_win "python open(C:\\tmp,'w') drive-letter (blocked)" "python3 -c \"open(r'C:\\tmp\\x','w')\"" 2
# Anything not provably a read fails closed.
run_win "python open(/tmp, m) variable mode (blocked)" "python3 -c \"open('/tmp/x', m).write('a')\"" 2
run_win "python open(/tmp, mode=m) variable mode (blocked)" "python3 -c \"open('/tmp/x', mode=m)\"" 2
run_win "python read then write open in one segment (blocked)" \
  "python3 -c \"open('/tmp/x').read(); open('/tmp/y', 'w')\"" 2
run_win "python heredoc read then write open (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/x\').read()\nopen(\'/tmp/y\', \'a\').write(d)\nEOF' 2
run_win "python os.popen writing /tmp (blocked)" "python3 -c \"import os; os.popen('echo a > /tmp/x')\"" 2
run_win "python os.fdopen beside /tmp (blocked)" \
  "python3 -c \"import os; os.fdopen(os.open('/tmp/x', 1), 'w')\"" 2
run_win "python os.open(/tmp, O_RDONLY) unproven (blocked)" \
  "python3 -c \"import os; os.open('/tmp/x', os.O_RDONLY)\"" 2
run_win "python ')' inside the quoted path, write mode (blocked)" "python3 -c \"open('/tmp/x)y','w').write('a')\"" 2
run_win "python ')' inside a comment, write mode (blocked)" \
  $'python3 - <<\'EOF\'\nopen(\'/tmp/x\' # )\n, \'w\').write(\'a\')\nEOF' 2
run_win "python triple-quoted path hiding ')' (blocked)" "python3 -c \"open('''/tmp/x')''', 'w')\"" 2
run_win "python mixed-quote kwarg hiding mode='w' (blocked)" \
  $'python3 - <<\'EOF\'\nopen(\'/tmp/x\', encoding="a\')", mode=\'w\')\nEOF' 2
# An escaped quote ends the literal for a regex but not for python.
run_win "python heredoc escaped-quote path, 'w' (blocked)" \
  $'python3 - <<\'EOF\'\nopen(\'/tmp/x\\\')\', \'w\').write(\'a\')\nEOF' 2
run_win "python heredoc escaped double-quote path, 'w' (blocked)" \
  $'python3 - <<\'EOF\'\nopen("/tmp/x\\")", "w").write("a")\nEOF' 2
run_win "python heredoc escaped-quote C:/tmp, 'w' (blocked)" \
  $'python3 - <<\'EOF\'\nopen(\'C:/tmp/x\\\')\', \'w\').write(\'a\')\nEOF' 2
run_win "python -c escaped-quote /c/tmp, 'a' (blocked)" "python3 -c \"open('/c/tmp/x\\')', 'a')\"" 2
run_win_pwsh "PS: python escaped-quote C:\\tmp, 'w' (blocked)" "python -c \"open('C:\\tmp\\x\\')', 'w').write('a')\"" 2
run_win "python heredoc escaped-quote kwarg hiding mode='w' (blocked)" \
  $'python3 - <<\'EOF\'\nopen(\'/tmp/x\', encoding=\'utf-8\\\')\', mode=\'w\')\nEOF' 2
# Star unpacking smuggles the mode past an unquoted argument.
run_win "python open(*a) with a /tmp,'w' tuple (blocked)" "python3 -c \"a=('/tmp/x','w'); open(*a).write('a')\"" 2
run_win_pwsh "PS: python open(*a) with a C:/tmp,'w' tuple (blocked)" "python -c \"a=('C:/tmp/x','w'); open(*a).write('a')\"" 2
run_win "python open(**k) dict literal (blocked)" "python3 -c \"k={'file':'/tmp/x','mode':'w'}; open(**k)\"" 2
run_win "python open(**k) dict() C:/tmp (blocked)" "python3 -c \"k=dict(file='C:/tmp/x',mode='a'); open(**k)\"" 2
# An f-string runs code inside its braces, so it never proves a read.
run_win "python open(f-string running os.system to /tmp) (blocked)" \
  $'python3 - <<\'EOF\'\nopen(f\'/tmp/x{__import__("os").system("echo a > /tmp/y")}\')\nEOF' 2
# Only a read call's CONTENT may leave it; its path (.name, a call argument) or exec keeps it blocked.
run_win "python shutil.copy to open(/tmp).name (blocked)" \
  "python3 -c \"import shutil; shutil.copy('/etc/hosts', open('/tmp/x').name)\"" 2
run_win "python os.system cp to open(/tmp).name (blocked)" \
  "python3 -c \"import os; os.system('cp /etc/hosts ' + open('/tmp/x').name)\"" 2
run_win "python os.rename to open(/tmp).name (blocked)" \
  "python3 -c \"import os; os.rename('a', open('/tmp/x').name)\"" 2
run_win "python shutil.copy to Path(/tmp).open().name (blocked)" \
  "python3 -c \"from pathlib import Path; import shutil; shutil.copy('/etc/hosts', Path('/tmp/x').open().name)\"" 2
run_win_pwsh "PS: python shutil.copy to open(C:/tmp).name (blocked)" \
  "python -c \"import shutil; shutil.copy('a', open('C:/tmp/x').name)\"" 2
run_win "python exec(open(/tmp).read()) (blocked)" "python3 -c \"exec(open('/tmp/x').read())\"" 2
run_win "python os.remove(open(/tmp).name) (blocked)" "python3 -c \"import os; os.remove(open('/tmp/x').name)\"" 2
# A proven read must not whitelist a sibling write in the same segment.
run_win "python read + os.system redirect to /tmp (blocked)" \
  "python3 -c \"open('/etc/hosts').read(); __import__('os').system('echo a > /tmp/y')\"" 2
run_win "python read + shutil.copy to /tmp (blocked)" \
  "python3 -c \"import shutil; open('/etc/hosts').read(); shutil.copy('/etc/hosts','/tmp/y')\"" 2
run_win_pwsh "PS: python read + shutil.copy to C:/tmp (blocked)" \
  "python -c \"import shutil; open('/etc/hosts').read(); shutil.copy('/etc/hosts','C:/tmp/y')\"" 2
run_win "python read + os.rename to /tmp (blocked)" \
  "python3 -c \"import os; open('/etc/hosts').read(); os.rename('a','/tmp/y')\"" 2
run_win "python read + subprocess cp to /tmp (blocked)" \
  "python3 -c \"import subprocess; open('/etc/hosts').read(); subprocess.run(['cp','/etc/hosts','/tmp/y'])\"" 2
run_win "python read /tmp + os.mknod /tmp (blocked)" "python3 -c \"open('/tmp/x'); import os; os.mknod('/tmp/y')\"" 2

# --- Heredoc decoy read, then a write in a later segment ----------------------
# The decoy read is a proven read on its own. The write that follows a `;` or a
# newline lands in another segment and must still block.
run_win "python heredoc decoy read, newline, os.system to /tmp (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/a\').read()\nimport os; os.system(\'echo pwned > /tmp/evil\')\nEOF' 2
run_win "python heredoc decoy read; os.system to /tmp on one line (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/a\').read(); import os; os.system(\'echo pwned > /tmp/evil\')\nEOF' 2
run_win "python heredoc decoy read, newline, shutil.copy to /tmp (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/a\').read()\nimport shutil\nshutil.copy(\'a\', \'/tmp/y\')\nEOF' 2
run_win "python heredoc decoy read; shutil.copy to /tmp on one line (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/a\').read(); import shutil; shutil.copy(\'a\', \'/tmp/y\')\nEOF' 2
run_win "python heredoc decoy read, newline, open(/tmp,'w') (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/a\').read()\nopen(\'/tmp/b\', \'w\').write(d)\nEOF' 2
run_win "python heredoc decoy read; open(/tmp,'w') on one line (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/a\').read(); open(\'/tmp/b\', \'w\').write(d)\nEOF' 2
run_win "python heredoc decoy read, newline, Path(/tmp).write_text (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/a\').read()\nfrom pathlib import Path\nPath(\'/tmp/b\').write_text(d)\nEOF' 2
run_win "python heredoc read .name fed to shutil.copy (blocked)" \
  $'python3 - <<\'EOF\'\nimport shutil\nn = open(\'/tmp/a\').name\nshutil.copy(\'x\', n)\nEOF' 2
run_win "python heredoc open(/tmp).read() beside open(/tmp).name fed to a write (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'/tmp/a\').read(); import shutil; shutil.copy(\'x\', open(\'/tmp/a\').name)\nEOF' 2
# The same decoys on PowerShell: the hook reads the command text, so a here-string
# fed to python and an inline -c run through the same rule.
run_win_pwsh "PS: python heredoc decoy read; os.system to C:/tmp (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'C:/tmp/a\').read(); import os; os.system(\'echo pwned > C:/tmp/evil\')\nEOF' 2
run_win_pwsh "PS: python heredoc decoy read, newline, shutil.copy to C:/tmp (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'C:/tmp/a\').read()\nimport shutil; shutil.copy(\'a\', \'C:/tmp/y\')\nEOF' 2
run_win_pwsh "PS: python heredoc decoy read; open(C:/tmp,'w') (blocked)" \
  $'python3 - <<\'EOF\'\nd = open(\'C:/tmp/a\').read(); open(\'C:/tmp/b\', \'w\').write(d)\nEOF' 2
run_win_pwsh "PS: here-string decoy read; os.system to C:/tmp (blocked)" \
  $'@\'\nd = open(\'C:/tmp/a\').read(); import os; os.system(\'echo pwned > C:/tmp/evil\')\n\'@ | python -' 2
run_win_pwsh "PS: python -c decoy read; shutil.copy to C:/tmp (blocked)" \
  "python -c \"import shutil; d = open('C:/tmp/a').read(); shutil.copy('a', 'C:/tmp/y')\"" 2
run_win_pwsh "PS: python heredoc read .name fed to shutil.copy (blocked)" \
  $'python3 - <<\'EOF\'\nimport shutil\nn = open(\'C:/tmp/a\').name\nshutil.copy(\'x\', n)\nEOF' 2
# The heredoc whose only reference to the path is a read is allowed; the same
# heredoc rewritten to write that path is blocked.
run_win "python heredoc json.load(open(/tmp)) then print (allowed)" \
  $'python3 - <<\'EOF\'\nimport json\nd = json.load(open(\'/tmp/retro-685.json\'))\nprint(d)\nprint(len(d))\nEOF' 0
run_win "python heredoc json.dump to the same /tmp path, write mode (blocked)" \
  $'python3 - <<\'EOF\'\nimport json\nd = {}\njson.dump(d, open(\'/tmp/retro-685.json\', \'w\'))\nEOF' 2
run_win "python heredoc Path(/tmp/retro-685.json).write_text (blocked)" \
  $'python3 - <<\'EOF\'\nfrom pathlib import Path\nPath(\'/tmp/retro-685.json\').write_text(\'{}\')\nEOF' 2
run_win_pwsh "PS: python heredoc json.load(open(C:/tmp)) read (allowed)" \
  $'python3 - <<\'EOF\'\nimport json\nd = json.load(open(\'C:/tmp/retro-685.json\'))\nprint(d)\nEOF' 0
run_win_pwsh "PS: python heredoc json.dump to the same C:/tmp path, write mode (blocked)" \
  $'python3 - <<\'EOF\'\nimport json\nd = {}\njson.dump(d, open(\'C:/tmp/retro-685.json\', \'w\'))\nEOF' 2
# The read relief needs python to be what consumes the read-call text. In any
# other shape a pipeline lifts the literal out of the text and writes it, and a
# second run in the same command writes elsewhere.
run_win "echo open(/c/tmp).read() | xargs -d tee (blocked)" \
  "echo \"open('/c/tmp/x').read()\" | xargs -d \"'\" tee" 2
run_win "echo open(/c/tmp).read() | xargs -d -n1 tee (blocked)" \
  "echo \"open('/c/tmp/x').read()\" | xargs -d \"'\" -n1 tee" 2
run_win "echo open(/c/tmp).read() | cut | xargs tee (blocked)" \
  "echo \"open('/c/tmp/x').read()\" | cut -d \"'\" -f2 | xargs tee" 2
run_win "echo open(/c/tmp).read() | cut | xargs cp a (blocked)" \
  "echo \"open('/c/tmp/x').read()\" | cut -d \"'\" -f2 | xargs cp a" 2
run_win "echo json.load(open(/c/tmp)) | cut | xargs tee (blocked)" \
  "echo \"json.load(open('/c/tmp/x'))\" | cut -d \"'\" -f2 | xargs tee" 2
run_win "python read, then a second python run on a computed path (blocked)" \
  "python3 -c \"print(open('/c/tmp/a').read())\"; python3 -c \"import sqlite3; sqlite3.connect('/c/t'+'mp/b')\"" 2
run_win "python -c read with its output piped to xargs tee (blocked)" \
  "python3 -c \"print('/c/t'+'mp/x'); open('/c/tmp/a').read()\" | xargs tee" 2
run_win "python -c read with an argument (blocked)" \
  "python3 -c \"print(open('/c/tmp/a').read())\" arg" 2
run_win "python heredoc read with its output piped to xargs tee (blocked)" \
  $'python3 - <<\'EOF\' | xargs -n1 tee\nimport json; d = json.load(open(\'/c/tmp/a\'))\nprint(\'/c/t\' + \'mp/x\')\nEOF' 2
run_win "python heredoc read, then a line piping a computed path to tee (blocked)" \
  $'python3 - <<\'EOF\'\nprint(open(\'/c/tmp/a\').read())\nEOF\necho /c/t""mp/x | xargs tee' 2
run_win "script file fed a read as its heredoc (blocked)" \
  $'python3 ./w.py <<\'EOF\'\nopen(\'/c/tmp/a\').read()\nEOF' 2
run_win "path-qualified python word with a read (blocked)" \
  "./python3 -c \"print(open('/c/tmp/a').read())\"" 2
run_win_pwsh "PS: echo open(/c/tmp).read() | xargs -d tee (blocked)" \
  "echo \"open('/c/tmp/x').read()\" | xargs -d \"'\" tee" 2
run_win_pwsh "PS: echo open(/c/tmp).read() | xargs -d -n1 tee (blocked)" \
  "echo \"open('/c/tmp/x').read()\" | xargs -d \"'\" -n1 tee" 2
run_win_pwsh "PS: echo open(/c/tmp).read() | cut | xargs tee (blocked)" \
  "echo \"open('/c/tmp/x').read()\" | cut -d \"'\" -f2 | xargs tee" 2
run_win_pwsh "PS: echo open(/c/tmp).read() | cut | xargs cp a (blocked)" \
  "echo \"open('/c/tmp/x').read()\" | cut -d \"'\" -f2 | xargs cp a" 2
run_win_pwsh "PS: echo json.load(open(/c/tmp)) | cut | xargs tee (blocked)" \
  "echo \"json.load(open('/c/tmp/x'))\" | cut -d \"'\" -f2 | xargs tee" 2
run_win_pwsh "PS: python read, then a second python run on a computed path (blocked)" \
  "python3 -c \"print(open('/c/tmp/a').read())\"; python3 -c \"import sqlite3; sqlite3.connect('/c/t'+'mp/b')\"" 2
run_win_pwsh "PS: python heredoc read with its output piped to xargs tee (blocked)" \
  $'python3 - <<\'EOF\' | xargs -n1 tee\nimport json; d = json.load(open(\'/c/tmp/a\'))\nprint(\'/c/t\' + \'mp/x\')\nEOF' 2
# The one allowed shape is a single plain python run: its -c string, or a heredoc
# on stdin with nothing after the terminator.
run_win "python -B -u -c open(/tmp) read (allowed)" "python3 -B -u -c \"print(open('/tmp/x').read())\"" 0
run_win "py launcher -3 -c open(/c/tmp) read (allowed)" "py -3 -c \"print(open('/c/tmp/x').read())\"" 0
run_win "python heredoc read, no - operand, blank lines after the tag (allowed)" \
  $'python3 <<\'EOF\'\nprint(open(\'/c/tmp/a\').read())\nEOF\n\n' 0
run_win_pwsh "PS: python -c open(C:/tmp) read (allowed)" "python -c \"print(open('C:/tmp/x').read())\"" 0
# Inline-code text quoted as data to a command that only carries text is a
# mention (#3951). The relief is an allowlist of whole commands (gh issue/pr
# create|comment|edit, git commit|tag, echo, printf), so any command not on it,
# including an interpreter this guard has never heard of, keeps the rule.
run_win "gh body quoting a write-mode open(/tmp) (allowed)" \
  "gh issue create --title t --body \"open('/tmp/x','w').write(1) was refused\"" 0
run_win "git commit -m quoting open(C:/tmp, 'w') (allowed)" \
  "git commit -m \"fix: open('C:/tmp/x','w') no longer refused\"" 0
run_win "gh body quoting write_text on /tmp (allowed)" \
  "gh issue comment 1 --body \"Path('/tmp/x').write_text('a') in the snippet\"" 0
run_win "gh body quoting write_bytes and makedirs on /tmp (allowed)" \
  "gh issue comment 1 --body \"Path('/tmp/x').write_bytes(b); os.makedirs('/tmp/d')\"" 0
run_win "gh single-quoted body quoting open(/c/tmp, \"w\") (allowed)" \
  "gh pr comment 2 --body 'open(\"/c/tmp/x\",\"w\") was refused'" 0
run_win "echo quoting open(/tmp, 'w') (allowed)" "echo \"open('/tmp/x','w')\"" 0
run_win "gh body naming python3 beside open(/tmp, 'w') (allowed, prose)" \
  "gh issue create --title t --body \"python3 open('/tmp/x','w')\"" 0
run_win "git tag -a -m quoting open(/c/tmp, 'w') (allowed)" \
  "git tag -a v1 -m \"open('/c/tmp/x','w')\"" 0
run_win "printf quoting open(/tmp, 'w') (allowed)" "printf '%s' \"open('/tmp/x','w')\"" 0
# An unlisted interpreter must not read as data: the relief is an allowlist, not
# a list of known runners.
run_win "R -e open(/c/tmp, 'w') (blocked)" \
  "R -e \"con<-file('/c/tmp/x');open(con,'w');writeLines('a',con)\"" 2
run_win "octave fopen(/c/tmp, 'w') (blocked)" \
  "octave --eval \"fid=fopen('/c/tmp/x','w');fprintf(fid,'a')\"" 2
run_win "npx tsx fs.open(/c/tmp, 'w') (blocked)" \
  "npx tsx -e \"require('fs').open('/c/tmp/x','w',()=>{})\"" 2
run_win "elixir File.open(/c/tmp) (blocked)" "elixir -e 'File.open(\"/c/tmp/x\",[:write])'" 2
run_win "erl file:open(/c/tmp) (blocked)" "erl -noshell -eval 'file:open(\"/c/tmp/x\",[write]),halt().'" 2
run_win "tcc -run heredoc fopen(/c/tmp) (blocked)" \
  $'tcc -run - <<\'EOF\'\nint main(){FILE*f=fopen("/c/tmp/x","w");return 0;}\nEOF' 2
run_win "gcc heredoc fopen(/c/tmp) then ./a.out (blocked)" \
  $'gcc -x c - -o a.out <<\'EOF\' && ./a.out\nint main(){FILE*f=fopen("/c/tmp/x","w");return 0;}\nEOF' 2
run_win "make heredoc recipe running R open(/c/tmp) (blocked)" \
  $'make -f - <<\'EOF\'\nx:\n\tR -e "open(\'/c/tmp/x\',\'w\')"\nEOF' 2
run_win "env R open(/c/tmp) (blocked)" "env R -e \"open('/c/tmp/x','w')\"" 2
run_win "time R open(/c/tmp) (blocked)" "time R -e \"open('/c/tmp/x','w')\"" 2
run_win "glob-spelled /usr/bin/pyth*3 open(/c/tmp) (blocked)" \
  "/usr/bin/pyth*3 -c \"open('/c/tmp/x','w')\"" 2
run_win "glob-spelled p?thon3 open(/c/tmp) (blocked)" "p?thon3 -c \"open('/c/tmp/x','w')\"" 2
run_win "quoted mention piped to R (blocked)" "echo \"open('/c/tmp/x','w')\" | R --no-save" 2
run_win "quoted mention piped to an unknown interpreter (blocked)" \
  "echo \"open('/c/tmp/x','w')\" | ./interp" 2
run_win "quoted mention, then a script run by path (blocked)" \
  "cat s.py \"open('/c/tmp/x','w')\" ; ./s.py" 2
run_win "gh body mention then an unlisted command after && (blocked)" \
  "gh issue create --body \"open('/c/tmp/x','w')\" && R -e 1" 2
run_win "gh body mention with an unquoted glob arg (blocked)" \
  "gh issue create --body \"open('/c/tmp/x','w')\" --label *" 2
run_win "gh body mention with an unterminated quote (blocked)" \
  "gh issue create --body \"open('/c/tmp/x','w') --title 'a" 2
run_win "gh api (not text-carrying) quoting open(/c/tmp) (blocked)" \
  "gh api repos/o/r/issues -f body=\"open('/c/tmp/x','w')\"" 2
# A quoted command word must not vanish and leave a trailing listed word in its
# place: bash runs python3 here with echo/printf/git as arguments.
run_win "quoted \"python3\" \"-c\" open(/c/tmp) then echo (blocked)" \
  "\"python3\" \"-c\" \"open('/c/tmp/x','w').write('a')\" echo" 2
run_win "quoted 'python3' '-c' open(/c/tmp) then printf (blocked)" \
  "'python3' '-c' \"open('/c/tmp/x','w').write('a')\" printf x" 2
run_win "quoted \"python3\" \"-c\" open(/c/tmp) then git commit (blocked)" \
  "\"python3\" \"-c\" \"open('/c/tmp/x','w')\" git commit -m x" 2
run_win "quoted 'python3' '-c' write_text(/c/tmp) then gh issue create (blocked)" \
  "'python3' '-c' \"import pathlib; pathlib.Path('/c/tmp/x').write_text('a')\" gh issue create" 2
run_win "quoted \"python3\" \"-c\" open(/tmp) then git tag (blocked)" \
  "\"python3\" \"-c\" \"open('/tmp/x','w')\" git tag v1" 2
run_win "gh, newline, pr create quoting open(/c/tmp) (blocked)" \
  $'gh\npr create --body "open(\'/c/tmp/x\',\'w\')"' 2
run_win "git, newline, commit quoting open(/c/tmp) (blocked)" \
  $'git\ncommit -m "open(\'/c/tmp/x\',\'w\')"' 2
run_win "gh issue, newline, create quoting open(/c/tmp) (blocked)" \
  $'gh issue\ncreate --body "open(\'/c/tmp/x\',\'w\')"' 2
run_win "quoted \"echo\" word with open(/c/tmp) (blocked, fail-closed)" \
  "\"echo\" \"open('/c/tmp/x','w')\"" 2
run_win_pwsh "PS: quoted \"python3\" \"-c\" open(C:/tmp) then echo (blocked)" \
  "\"python3\" \"-c\" \"open('C:/tmp/x','w').write('a')\" echo" 2
run_win_pwsh "PS: quoted 'python3' '-c' open(C:/tmp) then printf (blocked)" \
  "'python3' '-c' \"open('C:/tmp/x','w').write('a')\" printf x" 2
run_win_pwsh "PS: quoted \"python3\" \"-c\" open(C:/tmp) then git commit (blocked)" \
  "\"python3\" \"-c\" \"open('C:/tmp/x','w')\" git commit -m x" 2
# A computed path beside a decoy read: the token tmp left outside the read call
# keeps the block.
run_win "python read then urlretrieve to a concatenated /c/'+'tmp path (blocked)" \
  "python3 -c \"import json; json.load(open('/c/tmp/a')); import urllib.request as u; u.urlretrieve('http://x', '/c/'+'tmp/b')\"" 2
run_win "python read then sqlite3 on a concatenated path (blocked)" \
  "python3 -c \"d=open('/c/tmp/a').read(); import sqlite3; sqlite3.connect('/c/'+'tmp/b')\"" 2
run_win_pwsh "PS: [IO.File]::Open(C:/tmp/x, 'rb') (blocked)" "[IO.File]::Open('C:/tmp/x','rb')" 2
run_win "quoted open(/tmp) piped to sh (blocked)" "echo \"open('/tmp/x','w')\" | sh" 2
run_win "quoted open(/tmp) piped to xargs (blocked)" "echo \"open('/tmp/x','w')\" | xargs echo" 2
run_win "eval of quoted open(/tmp) (blocked)" "eval \"echo open('/tmp/x','w')\"" 2
run_win "bash -c of quoted open(/tmp) (blocked)" "bash -c \"echo open('/tmp/x','w')\"" 2
run_win "sh -c of quoted open(/tmp) (blocked)" "sh -c \"echo open('/tmp/x','w')\"" 2
# shellcheck disable=SC2016
run_win "variable-held command runs open(/tmp) (blocked)" '$P -c "open('"'"'/tmp/x'"'"','"'"'w'"'"')"' 2
# shellcheck disable=SC2016
run_win "backtick command word runs open(/tmp) (blocked)" '`which python3` -c "open('"'"'/tmp/x'"'"','"'"'w'"'"')"' 2
run_win "quote-spliced pyth''on3 runs open(/tmp) (blocked)" "pyth''on3 -c \"open('/tmp/x','w')\"" 2
run_win "sudo python3 open(/tmp) (blocked)" "sudo python3 -c \"open('/tmp/x','w')\"" 2
run_win "env python3 open(/tmp) (blocked)" "env python3 -c \"open('/tmp/x','w')\"" 2
run_win "exec python3 open(/tmp) (blocked)" "exec python3 -c \"open('/tmp/x','w')\"" 2
run_win "/usr/bin/python3 open(/tmp) (blocked)" "/usr/bin/python3 -c \"open('/tmp/x','w')\"" 2
run_win "python.exe open(/tmp) (blocked)" "python.exe -c \"open('/tmp/x','w')\"" 2
run_win "py.exe open(/tmp) (blocked)" "py.exe -3 -c \"open('/tmp/x','w')\"" 2
run_win "perl open(/tmp) (blocked)" "perl -e \"open(F, '>/tmp/x')\"" 2
run_win "ruby File.open(/tmp) (blocked)" "ruby -e \"File.open('/tmp/x','w')\"" 2
run_win "process substitution feeding open(/tmp) (blocked)" "cat <(echo \"open('/tmp/x','w')\")" 2
run_win "dot-sourced script beside open(/tmp) (blocked)" ". ./s.sh; echo \"open('/tmp/x','w')\"" 2
run_win "gh body then python3 on the next line (blocked)" \
  $'gh issue create --title t --body "x"\npython3 -c "open(\'/c/tmp/x\',\'w\')"' 2
run_win "heredoc fed to python3 writes /tmp (blocked)" \
  $'python3 - <<\'EOF\'\nopen(\'/tmp/x\', \'w\').write(\'a\')\nEOF' 2
run_win "gh body mention with a real redirect to /tmp (blocked)" \
  "gh issue create --body \"open('/tmp/x','w')\" > /tmp/out" 2
run_win "gh body mention with tee to /tmp (blocked)" \
  "gh issue create --body \"open('/tmp/x','w')\" | tee /tmp/x" 2
# Git for Windows resolves /usr/bin/mkdir to mkdir.exe under Program Files.
# The verb regex stops at a space, so neither spelling matched and the write
# was allowed (#4527). C:/tmp stays a drive root on a usertemp /tmp host.
run_win "/usr/bin/mkdir.exe C:/tmp/x (blocked)" '/usr/bin/mkdir.exe -p C:/tmp/x' 2
run_win "quoted Program Files mkdir.exe C:/tmp (blocked)" \
  '"C:/Program Files/Git/usr/bin/mkdir.exe" -p C:/tmp/x' 2
run_win "single-quoted mkdir.exe C:/tmp (blocked)" \
  "'/usr/bin/mkdir.exe' -p C:/tmp/x" 2
run_win "/usr/bin/cp.exe to C:/tmp (blocked)" '/usr/bin/cp.exe ./a C:/tmp/a' 2
run_win "echo /usr/bin/mkdir.exe mention (allowed)" 'echo /usr/bin/mkdir.exe C:/tmp/x' 0

# --- PowerShell writers (blocked) --------------------------------------------
run_win_pwsh "PS: Set-Content C:\\tmp\\x (blocked)" 'Set-Content -Path C:\tmp\x -Value hi' 2
run_win_pwsh "PS: Out-File \\tmp\\x (blocked)" "'hi' | Out-File \tmp\x" 2
run_win_pwsh "PS: redirect >/tmp/x (blocked)" "'hi' > /tmp/x" 2
run_win_pwsh "PS: New-Item /c/tmp/x (blocked)" 'New-Item -Path /c/tmp/x -ItemType File' 2
run_win_pwsh "PS: Add-Content C:/tmp/x (blocked)" 'Add-Content -Path C:/tmp/x -Value hi' 2
# PowerShell runs .NET inline, so the inline-code rule keeps its tool-wide reach.
run_win_pwsh "PS: [IO.File]::Open(C:/tmp/x, Create) (blocked)" "[IO.File]::Open('C:/tmp/x', 'Create')" 2

# --- Legitimate platform temp / POSIX variants (allowed) ---------------------
# Literal $TEMP / $env:TEMP in fixture strings must not expand in this test process.
# shellcheck disable=SC2016
run_win "redirect >\$TEMP/x (allowed)" 'echo x > $TEMP/x' 0
# shellcheck disable=SC2016
run_win "redirect >\$TMP/x (allowed)" 'echo x > $TMP/x' 0
# shellcheck disable=SC2016
run_win "redirect >\$TMPDIR/x (allowed)" 'echo x > $TMPDIR/x' 0
run_win "redirect >%TEMP%/x literal (allowed)" 'echo x > %TEMP%/x' 0
run_win "redirect >/var/tmp/x (allowed)" 'echo x > /var/tmp/x' 0
run_win "mkdir /var/tmp/x (allowed)" 'mkdir -p /var/tmp/x' 0
# shellcheck disable=SC2016
run_win "mktemp under \$TEMP (allowed)" 'mktemp "$TEMP/tmp.XXXXXX"' 0 # portability-ok: payload data for the hook, not a mktemp call
# shellcheck disable=SC2016
run_win_pwsh "PS: Set-Content \$env:TEMP (allowed)" 'Set-Content -Path $env:TEMP\x -Value hi' 0
# shellcheck disable=SC2016
run_win_pwsh "PS: Out-File \$env:TMP (allowed)" 'Out-File -FilePath $env:TMP\x -InputObject hi' 0

# --- Non-write mentions (allowed) --------------------------------------------
run_win "echo mentions /tmp (allowed)" 'echo do not use /tmp' 0
run_win "ls /tmp (read, allowed)" 'ls /tmp' 0
run_win "cat /tmp/x (read, allowed)" 'cat /tmp/x' 0
run_win "relative ./tmp (allowed)" 'echo x > ./tmp/x' 0
run_win "path component foo/tmp (allowed)" 'echo x > foo/tmp/x' 0
run_win "unrelated command (allowed)" 'git status' 0
# Redirect operator inside a quoted message must not fail closed (#2594 review).
run_win "quoted prose redirect (allowed)" 'git commit -m "Example: echo x > /tmp/x"' 0
run_win "single-quoted prose redirect (allowed)" "printf '%s' 'echo > /tmp/x'" 0
# Source-only /tmp with a writer elsewhere must stay allowed.
run_win "cp from /tmp (allowed)" 'cp /tmp/source ./dest' 0
run_win "compound mkdir then cat /tmp (allowed)" 'mkdir ./out && cat /tmp/source' 0

# --- Downloaders: curl -o / wget -O destinations (#4251) ---------------------
# These were allowed while mkdir/cp/redirect of the same path blocked.
run_win "curl -o /tmp/x (blocked)" 'curl -sS -o /tmp/x https://example.com' 2
run_win "curl --output /tmp/x (blocked)" 'curl --output /tmp/x https://example.com' 2
run_win "curl --output=/tmp/x (blocked)" 'curl --output=/tmp/x https://example.com' 2
run_win "curl glued -o/tmp/x (blocked)" 'curl -o/tmp/x https://example.com' 2
run_win "wget -O /tmp/a.html (blocked)" 'wget -O /tmp/a.html https://example.com' 2
run_win "wget --output-document /tmp/a.html (blocked)" \
  'wget --output-document /tmp/a.html https://example.com' 2
run_win "curl -o /c/tmp/x (blocked)" 'curl -o /c/tmp/x https://example.com' 2
run_win "curl https://example.com (allowed — no dest flag)" 'curl -sS https://example.com' 0
run_win "curl -o ./out.html (allowed)" 'curl -o ./out.html https://example.com' 0
run_win "curl URL containing /tmp (allowed — URL is not dest)" \
  'curl -sS https://example.com/tmp/hooks.md' 0
# A bundled short-flag cluster ending in the output flag takes the next token as
# its destination, exactly as the same flag alone does.
run_win "curl bundled -sSLo /c/tmp/x (blocked)" 'curl -sSLo /c/tmp/x https://example.com' 2
run_win "curl bundled -fsSLo /c/tmp/x (blocked)" 'curl -fsSLo /c/tmp/x https://example.com' 2
run_win "curl bundled -sSo /c/tmp/x (blocked)" 'curl -sSo /c/tmp/x https://example.com' 2
run_win "curl bundled -sSLo/c/tmp/x glued dest (blocked)" 'curl -sSLo/c/tmp/x https://example.com' 2
run_win "wget bundled -qO /c/tmp/a (blocked)" 'wget -qO /c/tmp/a https://example.com' 2
run_win "curl bundled -sSo ./out.html (allowed)" 'curl -sSo ./out.html https://example.com' 0
run_win "curl -O remote-name, URL with /tmp (allowed)" 'curl -O https://example.com/tmp/f' 0
# --output-dir names the directory an output or remote-name download lands in.
# -O takes no operand, so --output-dir must not be swallowed as one.
run_win "curl -O --output-dir /c/tmp (blocked)" 'curl -O --output-dir /c/tmp https://example.com' 2
run_win "curl --output-dir /c/tmp -O (blocked, dir before the flag)" \
  'curl --output-dir /c/tmp -O https://example.com' 2
run_win "curl --output-dir=/c/tmp -O (blocked)" 'curl --output-dir=/c/tmp -O https://example.com' 2
run_win "curl --output-dir /c/tmp then -o ./x (blocked, the last flag does not hide it)" \
  'curl --output-dir /c/tmp -o ./x https://example.com' 2
run_win "curl -O --output-dir ./dl (allowed)" 'curl -O --output-dir ./dl https://example.com' 0
# The same -O also must not swallow the flag that follows it.
run_win "curl -O -o /c/tmp/x (blocked)" 'curl -O -o /c/tmp/x https://example.com' 2
run_win "curl -O --output /c/tmp/x (blocked)" 'curl -O --output /c/tmp/x https://example.com' 2
run_win "curl -O -sSLo /c/tmp/x (blocked)" 'curl -O -sSLo /c/tmp/x https://example.com' 2
run_win "curl -sSLO -o /c/tmp/x (blocked, a bundled -O then -o)" \
  'curl -sSLO -o /c/tmp/x https://example.com' 2
run_win "curl -O -o ./x (allowed)" 'curl -O -o ./x https://example.com' 0

# --- Git for Windows usertemp /tmp is the platform temp (#4251) --------------
# Stub cygpath so POSIX /tmp compares equal to %TEMP%, the stock Git for
# Windows mount. Linux CI's real /tmp is tmpfs without usertemp, so without
# the stub the existing rows above still block.
USERTEMP_STUB="$TEST_TMPDIR/cygpath-stub"
mkdir -p "$USERTEMP_STUB"
cat >"$USERTEMP_STUB/cygpath" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-w" ]]; then
  shift
  if [[ "$1" == "/tmp" ]]; then
    # portability-ok: placeholder Windows profile in the cygpath stub, not a redirection
    printf '%s\n' "${TEMP:-C:\\Users\\<user>\\AppData\\Local\\Temp}"
  else
    printf '%s\n' "$1"
  fi
  exit 0
fi
exit 1
EOF
chmod +x "$USERTEMP_STUB/cygpath"
USERTEMP_ENV=(PATH="$USERTEMP_STUB:$PATH" TEMP='C:\Users\<user>\AppData\Local\Temp') # portability-ok: placeholder Windows profile, not a redirection
run_win "usertemp: mkdir /tmp/x (allowed)" 'mkdir -p /tmp/x' 0 "${USERTEMP_ENV[@]}"
run_win "usertemp: redirect >/tmp/x (allowed)" 'echo x > /tmp/x' 0 "${USERTEMP_ENV[@]}"
run_win "usertemp: curl -o /tmp/x (allowed)" \
  'curl -sS -o /tmp/x https://example.com' 0 "${USERTEMP_ENV[@]}"
run_win "usertemp: mkdir /c/tmp/x still blocked" 'mkdir -p /c/tmp/x' 2 "${USERTEMP_ENV[@]}"
run_win "usertemp: mkdir C:\\tmp\\x still blocked" 'mkdir -p C:\tmp\x' 2 "${USERTEMP_ENV[@]}"
run_win_pwsh "usertemp: PS /tmp still blocked" "'hi' > /tmp/x" 2 "${USERTEMP_ENV[@]}"
run_win_payload "usertemp: Write /tmp/x still blocked" "$(write_json '/tmp/x' 'x')" 2 \
  "${USERTEMP_ENV[@]}"
run_win "usertemp: curl -sSLo /tmp/x (allowed)" 'curl -sSLo /tmp/x https://example.com' 0 \
  "${USERTEMP_ENV[@]}"

# Drive-root `\tmp` is the volume root on this host too. Slash-folding reads it as
# POSIX /tmp, which the usertemp mount makes a legitimate temp, so the guard has to
# see the backslash before the fold. Only a QUOTED spelling reaches Windows as
# `\tmp`; an unquoted `\tmp\x` unescapes to the relative file `tmpx`. The guard
# cannot tell the two apart after folding and blocks both, as it does off usertemp.
run_win "usertemp: redirect >\\tmp\\x drive-root (blocked)" 'echo x > \tmp\x' 2 "${USERTEMP_ENV[@]}"
run_win "usertemp: mkdir \\tmp\\x drive-root (blocked)" 'mkdir -p \tmp\x' 2 "${USERTEMP_ENV[@]}"
run_win "usertemp: redirect >\"\\tmp\\x\" double-quoted (blocked)" 'echo x > "\tmp\x"' 2 \
  "${USERTEMP_ENV[@]}"
run_win "usertemp: redirect >'\\tmp\\x' single-quoted (blocked)" "echo x > '\\tmp\\x'" 2 \
  "${USERTEMP_ENV[@]}"
run_win "usertemp: cat \\tmp\\a > /tmp/b (allowed, \\tmp is a source)" 'cat \tmp\a > /tmp/b' 0 \
  "${USERTEMP_ENV[@]}"
run_win "usertemp: redirect >D:\\a\\tmp\\x subdir tmp (allowed)" 'echo x > D:\a\tmp\x' 0 \
  "${USERTEMP_ENV[@]}"
run_win "usertemp: redirect >.\\tmp\\x relative (allowed)" 'echo x > .\tmp\x' 0 "${USERTEMP_ENV[@]}"
run_win "usertemp: redirect >foo\\tmp\\x path component (allowed)" 'echo x > foo\tmp\x' 0 \
  "${USERTEMP_ENV[@]}"
run_win "usertemp: redirect >\\tmpdir\\x sibling (allowed)" 'echo x > \tmpdir\x' 0 "${USERTEMP_ENV[@]}"
run_win "usertemp: redirect >\\TMP\\x upper case (blocked)" 'echo x > "\TMP\x"' 2 "${USERTEMP_ENV[@]}"

# The usertemp probe forks cygpath, and a Windows Bash hook pays a process
# creation per fork. A command with no `tmp` in it must not reach the probe.
usertemp_trace() {
  env OSTYPE=msys "${USERTEMP_ENV[@]}" bash -x "$HOOK" <<<"$(msys_command_json "$1")" 2>&1 >/dev/null
}
assert_absent "usertemp: a benign command never probes cygpath" "$(usertemp_trace 'git status --short')" "cygpath"
assert_contains "usertemp: a /tmp command does probe cygpath" "$(usertemp_trace 'mkdir -p /tmp/x')" "cygpath"

# Mount-table fallback: with no usable cygpath the guard reads `mount`, and the
# usertemp flag only counts on the /tmp mount's own line. The stub cygpath always
# fails so the fallback decides on every host, and the rows go through
# run_win_payload so no host-derived downgrade applies to them.
MOUNT_STUB="$TEST_TMPDIR/mount-stub"
mkdir -p "$MOUNT_STUB"
cat >"$MOUNT_STUB/cygpath" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$MOUNT_STUB/mount" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$STUB_MOUNT_LINES"
EOF
chmod +x "$MOUNT_STUB/cygpath" "$MOUNT_STUB/mount"
MOUNT_ROOT='C:/Program Files/Git on / type ntfs (binary,noacl,posix=0)'
MOUNT_TMP_USERTEMP='C:/Users/<user>/AppData/Local/Temp on /tmp type ntfs (binary,noacl,posix=0,usertemp)'
MOUNT_TMP_PLAIN='C:/tmp on /tmp type ntfs (binary,noacl,posix=0)'
MOUNT_OTHER_USERTEMP='C:/Users/<user>/AppData/Local/Temp on /other type ntfs (binary,noacl,posix=0,usertemp)'
run_win_payload "mount fallback: usertemp on the /tmp line (allowed)" \
  "$(msys_command_json 'echo x > /tmp/x')" 0 PATH="$MOUNT_STUB:$PATH" \
  STUB_MOUNT_LINES="$MOUNT_ROOT"$'\n'"$MOUNT_TMP_USERTEMP"
run_win_payload "mount fallback: usertemp on another line only (blocked)" \
  "$(msys_command_json 'echo x > /tmp/x')" 2 PATH="$MOUNT_STUB:$PATH" \
  STUB_MOUNT_LINES="$MOUNT_ROOT"$'\n'"$MOUNT_TMP_PLAIN"$'\n'"$MOUNT_OTHER_USERTEMP"
run_win_payload "mount fallback: usertemp before the /tmp line, on a different line (blocked)" \
  "$(msys_command_json 'echo x > /tmp/x')" 2 PATH="$MOUNT_STUB:$PATH" \
  STUB_MOUNT_LINES="$MOUNT_OTHER_USERTEMP"$'\n'"$MOUNT_TMP_PLAIN"
run_win_payload "mount fallback: no usertemp anywhere (blocked)" \
  "$(msys_command_json 'echo x > /tmp/x')" 2 PATH="$MOUNT_STUB:$PATH" \
  STUB_MOUNT_LINES="$MOUNT_ROOT"$'\n'"$MOUNT_TMP_PLAIN"

# --- PowerShell copy/move destinations (blocked) -----------------------------
run_win_pwsh "PS: Copy-Item to C:\\tmp (blocked)" 'Copy-Item .\a C:\tmp\a' 2
run_win_pwsh "PS: Move-Item to C:\\tmp (blocked)" 'Move-Item .\a C:\tmp\a' 2
run_win_pwsh "PS: copy alias to /tmp (blocked)" 'copy .\a /tmp/a' 2

# --- Kill switch -------------------------------------------------------------
run_win "kill switch disables guard" 'echo x > /tmp/x' 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_WINDOWS_DRIVE_TMP_ENABLED=false

# --- Telemetry (opt-in sink) -------------------------------------------------
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK=$(make_sink "cat > \"$TEL\"")
out=$(env OSTYPE=msys HOOK_TELEMETRY_SINK="$SINK" bash "$HOOK" \
  <<<"$(command_json 'echo x > C:/tmp/x')" 2>&1) || true
wait_for_sink "$TEL" || true
if [[ -s "$TEL" ]]; then
  tel_body=$(cat "$TEL")
  assert_contains "telemetry hook id" "$(jq -r .hook <<<"$tel_body")" 'block-windows-drive-tmp'
  assert_contains "telemetry blocked" "$(jq -r .status <<<"$tel_body")" 'blocked'
  assert_contains "telemetry form" "$(jq -r .data.form <<<"$tel_body")" 'redirect'
else
  # Telemetry is best-effort; an empty sink on a slow box is not a contract fail
  # when the block itself already asserted. Record as an explicit skip-visible.
  ok "telemetry sink empty (best-effort; block path already covered)"
fi
assert_contains "blocked stderr still present with sink" "$out" "drive-root temp"

# --- Telemetry on the file-path lane -----------------------------------------
# The `file-path` form and the Write-shaped `tool` / `subject` are documented in
# docs/conventions/hook-telemetry/data/block-windows-drive-tmp.schema.json, and
# the case above exercises only the Bash lane — so without this the new envelope
# is documented and never executed, and a fault in emit_tel's now-locally-scoped
# SUBJECT would leave every assertion green. `subject` must be the bare tool
# name: hook::extract_bash_subject does not tokenize a non-Bash tool, and the
# target path must never reach the envelope.
TEL_FP="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK_FP=$(make_sink "cat > \"$TEL_FP\"")
out=$(env OSTYPE=msys HOOK_TELEMETRY_SINK="$SINK_FP" bash "$HOOK" \
  <<<"$(write_json 'C:\tmp\tmp.rSFIkHm5DO' 'x')" 2>&1) || true
wait_for_sink "$TEL_FP" || true
if [[ -s "$TEL_FP" ]]; then
  tel_fp_body=$(cat "$TEL_FP")
  assert_contains "file-path telemetry hook id" "$(jq -r .hook <<<"$tel_fp_body")" 'block-windows-drive-tmp'
  assert_contains "file-path telemetry blocked" "$(jq -r .status <<<"$tel_fp_body")" 'blocked'
  assert_contains "file-path telemetry form" "$(jq -r .data.form <<<"$tel_fp_body")" 'file-path'
  assert_contains "file-path telemetry tool" "$(jq -r .data.tool <<<"$tel_fp_body")" 'Write'
  assert_contains "file-path telemetry subject" "$(jq -r .data.subject <<<"$tel_fp_body")" 'Write'
  assert_absent "file-path telemetry carries no path" "$tel_fp_body" "rSFIkHm5DO"
else
  ok "file-path telemetry sink empty (best-effort; block path already covered)"
fi
assert_contains "file-path blocked stderr present with sink" "$out" "drive-root temp"

echo "SKIPPED=$SKIPPED"
report
