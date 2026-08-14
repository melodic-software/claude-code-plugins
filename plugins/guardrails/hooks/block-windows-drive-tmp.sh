#!/usr/bin/env bash
# PreToolUse hook: block writes whose target is a Windows drive-root temp path.
# Triggered on Bash and PowerShell tool calls.
#
# On Windows (Git Bash / MSYS / Cygwin), a hardcoded POSIX `/tmp` path resolves to
# `<current-drive>:\tmp` (e.g. `C:\tmp`) rather than the platform temp directory
# (`%TEMP%` — typically `C:\Users\<user>\AppData\Local\Temp`). Drive-letter and
# drive-relative spellings (`C:\tmp`, `/c/tmp`, `\tmp`) are the same sink. Nothing
# else in the guard surface noticed those writes, so residue accumulated silently
# at the volume root (#2594).
#
# This guard FAILS CLOSED on a write-shaped reference to those roots and points
# the operator at the platform temp. It does NOT engage on non-Windows hosts
# (where `/tmp` is the real POSIX temp). It does NOT block legitimate platform
# temp usage: `%TEMP%` / `$TEMP` / `$TMP` / `$env:TEMP` / `$TMPDIR` expansions,
# or `/var/tmp`.
#
# Detection is a static matcher over the literal command string — it does not
# evaluate shell / PowerShell expansions. Scope residual: an expansion-built
# path (`$x` where x=/tmp) is invisible here; that is friction against accidental
# hardcoded roots, not a sandbox.
#
# BLOCKING: exits 2 on a detected drive-root temp write.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_WINDOWS_DRIVE_TMP"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) skips like the empty-COMMAND guard below; rc 2 (read timed out
# before a complete payload) FAILS CLOSED — the guard cannot evaluate the tool
# call, and a silent skip would pass exactly the traffic this guard exists to
# stop. buffer_stdin already printed the BLOCKED reason to stderr. Buffering
# does not require jq (hook::buffer_stdin's own JSON-completeness check is
# jq-optional), so it runs before the jq gate below.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload, and this guard FAILS CLOSED on its
# absence — same posture as the other Bash/PowerShell blocking guards (#2146).
hook::require_jq_blocking "guardrails-block-windows-drive-tmp" "block_windows_drive_tmp_enabled"

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

# Non-Windows hosts: /tmp is the real POSIX temp. Skip entirely. Tests force
# OSTYPE=msys to exercise the Windows lane on Linux CI.
case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*) exit 0 ;;
esac

MAX_COMMAND_LEN=16384
SUBJECT=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:$tool,subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-windows-drive-tmp" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block() {
  local form="$1"
  # Single-quoted on purpose: the Fix line must show literal $TEMP / $env:TEMP
  # spellings to the agent, not expand them in the hook process.
  # shellcheck disable=SC2016
  printf '%s\n' \
    'BLOCKED: write target is a Windows drive-root temp path (resolves to <drive>:\tmp), not the platform temp directory.' \
    'On Windows, POSIX /tmp, MSYS /<drive>/tmp, C:\tmp, and drive-root \tmp land at the volume root and accumulate silently.' \
    'Fix: write under the platform temp instead — %TEMP% / $TEMP / $env:TEMP (or $TMP / $TMPDIR when they already point there). /var/tmp is also fine.' >&2
  emit_tel "blocked" "$form"
  exit 2
}

# Above this length the command is not parsed — fail closed (same ceiling as the
# other argv-faithful Bash guards).
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  block "too-long"
fi

# Slash-normalize so C:\tmp, C:/tmp, and \tmp share one matcher. Lowercase for
# case-insensitive Windows path compare without relying on bash [[ =~ ]] flags.
NORM=$(printf '%s' "${COMMAND//\\//}" | tr '[:upper:]' '[:lower:]')

# True when <haystack> carries a drive-root tmp path reference:
#   /tmp[/...]           — POSIX form (Git Bash maps this to <drive>:\tmp)
#   /x/tmp[/...]         — MSYS drive form (/c/tmp → C:\tmp)
#   x:/tmp[/...]         — Windows drive-letter form
# Left boundary excludes a relative `./tmp` and a `/var/tmp` suffix (the char
# before `/tmp` in `/var/tmp` is `r`). Right boundary is a path component end.
has_drive_root_tmp() {
  local s="$1"
  # POSIX /tmp — not ./tmp, not /var/tmp, not /tmpdir
  if [[ "$s" =~ (^|[^[:alnum:]._/])\/tmp(\/|[^[:alnum:]_./-]|$) ]]; then
    return 0
  fi
  # MSYS /<drive>/tmp
  if [[ "$s" =~ (^|[^[:alnum:]._/])\/[a-z]\/tmp(\/|[^[:alnum:]_./-]|$) ]]; then
    return 0
  fi
  # Drive-letter X:/tmp
  if [[ "$s" =~ (^|[^[:alnum:]])[a-z]:\/tmp(\/|[^[:alnum:]_./-]|$) ]]; then
    return 0
  fi
  return 1
}

# Write-shaped signal: a redirect whose target word is a drive-root tmp path.
# Covers `> /tmp/x`, `>/tmp/x`, `>>/tmp/x`, `2>/tmp/err`, `&>/tmp/x`.
has_redirect_to_drive_root_tmp() {
  local s="$1"
  # Optional fd digits and optional & (&>), then > or >>, optional space/quotes,
  # then a drive-root tmp path. Angle brackets in the right-boundary class are
  # literal characters (not GNU \< \> word-boundaries) — keep them unescaped so
  # the portability gate does not flag this ERE. portability-ok: bash [[ =~ ]]
  # character class literals, not grep -E word boundaries
  if [[ "$s" =~ (^|[^>&])\&?[0-9]*\>\>?[[:space:]]*[\"\']?(\/tmp|\/[a-z]\/tmp|[a-z]:\/tmp)(\/|[\"\'[:space:]\;|&<>()]|$) ]]; then
    return 0
  fi
  return 1
}

# Write-shaped signal: a known producer / destination utility alongside a
# drive-root tmp path. Echo/printf alone are NOT enough (they write stdout, and
# a prose mention of /tmp must stay allowed).
has_write_utility_with_drive_root_tmp() {
  local s="$1"
  has_drive_root_tmp "$s" || return 1

  # POSIX creators / copy destinations / tee
  if [[ "$s" =~ (^|[[:space:];|&])(tee|mktemp|mkdir|touch|install|cp|mv|dd|install\.exe|tee\.exe)([[:space:]]|$) ]]; then
    return 0
  fi
  # PowerShell file-write cmdlets (and common aliases ac / ni). `sc` is NOT
  # matched alone — on PS 7 it is sc.exe; block-hook-bypass already models the
  # 5.1 Set-Content form separately. Out-File / Set-Content / Add-Content /
  # Tee-Object / New-Item are unambiguous writers.
  if [[ "$s" =~ (^|[[:space:];|&]|/)(set-content|add-content|out-file|tee-object|new-item|export-clixml|export-csv)([[:space:]]|:|$) ]]; then
    return 0
  fi
  if [[ "$s" =~ (^|[[:space:];|&])(ac|ni)([[:space:]]|$) ]]; then
    return 0
  fi
  # Inline python write opening a drive-root tmp path
  if [[ "$s" =~ (open|write_text|write_bytes|makedirs)\( ]] &&
    [[ "$s" =~ (\/tmp|\/[a-z]\/tmp|[a-z]:\/tmp) ]]; then
    return 0
  fi
  return 1
}

if has_redirect_to_drive_root_tmp "$NORM"; then
  block "redirect"
fi

if has_write_utility_with_drive_root_tmp "$NORM"; then
  block "write-utility"
fi

emit_tel "ok" ""
exit 0
