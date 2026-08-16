#!/usr/bin/env bash
# PreToolUse hook: block an EXPORTED MSYS path-conversion suppressor.
#
# On Windows, Git Bash's MSYS runtime rewrites POSIX-looking argv into Windows
# form before spawning a native binary, so `git worktree add /d/worktrees/x`
# reaches git.exe as `D:/worktrees/x` and lands where the author meant. Setting
# `MSYS_NO_PATHCONV` or `MSYS2_ARG_CONV_EXCL` switches that rewriting off. Once
# EXPORTED, it stays off for every later command in the same command string —
# including commands the author was not thinking about when they set it.
#
# The consequence is the drive-root phantom tree: git.exe resolves an
# unconverted leading `/` against the CURRENT DRIVE, so `/d/worktrees/x` becomes
# `<current-drive>:\d\worktrees\x`. That is how `D:\d` was created a third time
# (#2870), by a lane that exported the variable to work around an unrelated
# problem — MSYS mangling a `<rev>:<path>` argument — seven segments earlier.
#
# WHY THIS SHAPE AND NOT A PATH MATCHER. The offending command's path argument
# was textually identical to one the same lane had already run successfully. A
# guard keyed on the `/[a-z]/` path form has a FALSE NEGATIVE on the real
# incident, and measured 45.7% firing across 14,234 real Bash commands — 81% on
# `git worktree add` alone. The export form fires on 0.32% of the same corpus
# and leaves the safe per-command-prefix idiom (193 uses) untouched. The
# distinction is mechanical, not heuristic; `git rev-parse --sq-quote` shows
# exactly what git.exe received:
#
#   bash -c 'git rev-parse --sq-quote /d/probe'                    -> 'D:/probe'
#   bash -c 'MSYS_NO_PATHCONV=1; git rev-parse --sq-quote /d/probe' -> 'D:/probe'
#   bash -c 'export MSYS_NO_PATHCONV=1; git rev-parse ... /d/probe' -> '/d/probe'
#   bash -c 'MSYS_NO_PATHCONV=1 git ... /d/first; git ... /d/second'
#                                            -> '/d/first' then 'D:/second'
#
# So a bare assignment does nothing (the MSYS runtime reads the environment, and
# an unexported shell variable is not in it), the per-command prefix scopes the
# suppression exactly as intended, and only the exported form leaks.
#
# SIBLING, NOT A SECOND WAY. plugins/guardrails/hooks/block-windows-drive-tmp.sh
# guards the same family — drive-root residue on Windows — but is a PATH-SHAPE
# and WRITE-TARGET matcher scoped to `tmp`, on `Bash|PowerShell`, with
# tmp-specific allowances (`/var/tmp`, `%TEMP%`). This guard is an
# ENVIRONMENT-VARIABLE matcher with no path component at all. The scopes are
# disjoint: neither would fire on the other's cases, which is why they are two
# hooks rather than one overloaded matcher. See that file's header for the
# reciprocal note.
#
# TWO LEAKING FORMS ARE MATCHED, not one: the `export` family, and a prefix
# whose command word is a SHELL (`MSYS_NO_PATHCONV=1 bash -c '...'`), which
# leaks into every command inside that child. See `leaks_into_child_shell`.
#
# DECLARED COVERAGE GAPS (out of scope, documented rather than hidden): a
# suppressor exported by a SCRIPT the command invokes rather than in the command
# string; `set -a` followed by a bare assignment; a value assembled through an
# expansion; a prefix on a non-shell interpreter that itself spawns native
# children (`MSYS_NO_PATHCONV=1 python script.py`); and any spawner outside the
# Bash/PowerShell tool surfaces (CI runners, Node/Python `subprocess`), which no
# PreToolUse hook can see.
#
# Kill switch: block_exported_msys_pathconv_enabled userConfig option.
#
# BLOCKING: exits 2 on a detected exported suppressor.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_EXPORTED_MSYS_PATHCONV"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# rc 1 (empty stdin) skips like the empty-COMMAND guard below; rc 2 (read timed
# out before a complete payload) FAILS CLOSED — the guard cannot evaluate the
# tool call, and a silent skip would pass exactly the traffic this guard exists
# to stop. buffer_stdin already printed the BLOCKED reason to stderr.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload, and this guard FAILS CLOSED on its
# absence — same posture as the other Bash/PowerShell blocking guards (#2146).
hook::require_jq_blocking "guardrails-block-exported-msys-pathconv" "block_exported_msys_pathconv_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || jq_rc=$?
if ((jq_rc == 2)); then
  echo "BLOCKED: the hook payload could not be parsed." >&2
  exit 2
fi
((jq_rc != 0)) && exit 0

# A NUL byte in EITHER field is fail-CLOSED (#2136 / #2122).
if ((HOOK_JQ_FIELDS_NUL)); then
  echo "BLOCKED: the payload carries a NUL byte, which a command cannot reliably carry." >&2
  echo "What a guard can read is not dependably what would run, so this is refused rather than matched." >&2
  echo "Fix: reissue the tool call without the embedded NUL." >&2
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"

# Non-Windows hosts: MSYS argv rewriting does not exist, so neither variable has
# any effect and nothing here is a defect. Tests force OSTYPE=msys to exercise
# the Windows lane on Linux CI.
case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*) exit 0 ;;
esac

# Cheap substring pre-filter BEFORE any length ceiling or parsing: a command
# that never names either variable cannot be this defect at any length, so it
# leaves without paying for the matcher. Measured: 14,188 of 14,234 real Bash
# commands exit here.
if [[ "$COMMAND" != *MSYS_NO_PATHCONV* && "$COMMAND" != *MSYS2_ARG_CONV_EXCL* ]]; then
  exit 0
fi

MAX_COMMAND_LEN=16384

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local subject data
  subject=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$subject" --arg form "$2" \
    '{tool:$tool,subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-exported-msys-pathconv" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block() {
  local form="$1"
  # Single-quoted on purpose: the Fix line must show the literal spellings to
  # the agent, not expand them in the hook process.
  # shellcheck disable=SC2016
  printf '%s\n' \
    'BLOCKED: exporting MSYS_NO_PATHCONV / MSYS2_ARG_CONV_EXCL switches off MSYS path conversion for EVERY later command in this command string.' \
    'A later path argument then reaches a Windows-native program unconverted, and git resolves a leading / against the CURRENT DRIVE:' \
    '  git worktree add /d/worktrees/x   ->   <current-drive>:/d/worktrees/x   (a phantom tree, and a run that measured the wrong thing)' \
    'Fix, in preference order:' \
    '  1. Use Windows-native paths for path arguments -- git -C <repo-root> show ... -- so the question does not arise.' \
    '  2. If you need the suppressor for a <rev>:<path> argument, use it as a PER-COMMAND PREFIX, which scopes it to that one command:' \
    '       MSYS_NO_PATHCONV=1 git show "origin/main:.github/workflows/ci.yml"' \
    'A bare assignment (MSYS_NO_PATHCONV=1; ...) has no effect at all -- the MSYS runtime reads the environment, so only export leaks.' \
    'See docs/conventions/windows-path-emit/README.md.' >&2
  emit_tel "blocked" "$form"
  exit 2
}

# Past this length the command is not parsed. It already named one of the two
# variables (pre-filter above), so failing closed here refuses a command that is
# both suspect and unreadable rather than waving it through.
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  block "too-long"
fi

# The export forms. `export`/`declare -x`/`typeset -x` may carry other
# assignments before the one that matters (`export A=1 MSYS_NO_PATHCONV=1`), so
# leading `NAME=value` pairs are skipped. A BARE assignment is deliberately not
# matched: it does not enter the environment and therefore does not suppress.
is_exported_suppressor() {
  local s="$1"
  [[ "$s" =~ (^|[^[:alnum:]_.-])(export|declare[[:space:]]+-x|typeset[[:space:]]+-x)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(MSYS_NO_PATHCONV|MSYS2_ARG_CONV_EXCL)([=[:space:]\;\|\&]|$) ]]
}

# A prefix whose command word is a SHELL leaks just as far, because the child
# shell inherits the suppressor for every command inside it — the prefix scopes
# to one PROCESS, and when that process is an interpreter, "one process" is the
# whole script. Measured behaviorally:
#
#   bash -c 'MSYS_NO_PATHCONV=1 git ... /d/a; git ... /d/b'  -> '/d/a' then 'D:/b'  scoped
#   MSYS_NO_PATHCONV=1 bash -c 'git ... /d/a; git ... /d/b'  -> '/d/a' then '/d/b'  LEAKS
#   env MSYS_NO_PATHCONV=1 bash -c '...'                     -> leaks the same way
#
# Cost of covering it, measured on the same 14,234-command corpus: ONE match,
# which the export rule above already blocks. So this closes a real gap for no
# additional false positives.
leaks_into_child_shell() {
  local s="$1"
  [[ "$s" =~ (^|[^[:alnum:]_./-])(env[[:space:]]+([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*)?(MSYS_NO_PATHCONV|MSYS2_ARG_CONV_EXCL)=[^[:space:]]*[[:space:]]+([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(env[[:space:]]+)?[^[:space:]]*(bash|sh|dash|zsh|ksh)(\.exe)?([[:space:]]|$) ]]
}

if is_exported_suppressor "$COMMAND"; then
  block "export"
fi

if leaks_into_child_shell "$COMMAND"; then
  block "child-shell"
fi

emit_tel "ok" ""
exit 0
