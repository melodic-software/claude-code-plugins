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
run_win() {
  local label="$1" command="$2"
  shift 2
  run_win_payload "$label" "$(command_json "$command")" "$@"
}

run_win_pwsh() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$(pwsh_command_json "$command")" 2>&1)
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
# MSYS argv rewriting converts an argument only when the argument is ENTIRELY a
# POSIX-absolute path: `/c/tmp/x` becomes `C:/tmp/x`, while `mkdir -p /c/tmp/x`
# passes through untouched. Every command fixture below is multi-token, so the
# shared command_json / pwsh_command_json are already safe for them and omit
# MSYS_NO_PATHCONV correctly (the shared PATH-payload builders — write_json and
# siblings — do set it, because a file_path IS a lone path). These local
# builders set it explicitly so a future lone-path command fixture cannot
# silently become a drive-letter payload and stop exercising the MSYS arm.
msys_command_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}'
}
msys_pwsh_command_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg cmd "$1" '{tool_name:"PowerShell",tool_input:{command:$cmd}}'
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
run_win_payload "NotebookEdit file_path /tmp/n.ipynb (blocked)" \
  "$(notebook_json '/tmp/n.ipynb' 'x')" 2
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
  [ .hooks.PreToolUse[]
    | select([.hooks[].command] | any(contains($h)))
    | .matcher | split("|")[] ]
  | sort | join(" ")' "$HOOKS_JSON" 2>/dev/null)
assert_eq "hooks.json routes the guard to exactly the intended tools" \
  "Bash Edit MultiEdit NotebookEdit PowerShell Write" "$reg"
# The registration must also NAME A FILE THAT EXISTS — a command path typo
# registers cleanly and then fails to run on every tool call.
reg_cmd=$(jq -r --arg h "block-windows-drive-tmp.sh" '
  [ .hooks.PreToolUse[].hooks[].command | select(contains($h)) ] | first // ""' \
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

# --- PowerShell writers (blocked) --------------------------------------------
run_win_pwsh "PS: Set-Content C:\\tmp\\x (blocked)" 'Set-Content -Path C:\tmp\x -Value hi' 2
run_win_pwsh "PS: Out-File \\tmp\\x (blocked)" "'hi' | Out-File \tmp\x" 2
run_win_pwsh "PS: redirect >/tmp/x (blocked)" "'hi' > /tmp/x" 2
run_win_pwsh "PS: New-Item /c/tmp/x (blocked)" 'New-Item -Path /c/tmp/x -ItemType File' 2
run_win_pwsh "PS: Add-Content C:/tmp/x (blocked)" 'Add-Content -Path C:/tmp/x -Value hi' 2

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
run_win "mktemp under \$TEMP (allowed)" 'mktemp "$TEMP/tmp.XXXXXX"' 0
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
  <<<"$(command_json 'echo x > /tmp/x')" 2>&1) || true
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

report
