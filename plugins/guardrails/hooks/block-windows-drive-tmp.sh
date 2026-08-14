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

# Replace `>` that sit inside single- or double-quoted spans so a prose mention
# such as `git commit -m "echo x > /tmp/x"` is not treated as a redirect, while
# a real redirect whose *target* is quoted (`echo x > "/tmp/x"`) still matches.
mask_quoted_redirect_ops() {
  local s="$1" out="" i=0 c quote=""
  local -i len=${#s}
  while ((i < len)); do
    c="${s:i:1}"
    if [[ -n "$quote" ]]; then
      if [[ "$c" == "$quote" ]]; then
        quote=""
        out+="$c"
      elif [[ "$c" == '>' ]]; then
        out+='#'
      else
        out+="$c"
      fi
    else
      if [[ "$c" == "'" || "$c" == '"' ]]; then
        quote="$c"
      fi
      out+="$c"
    fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# Write-shaped signal: a redirect whose target word is a drive-root tmp path.
# Covers `> /tmp/x`, `>/tmp/x`, `>>/tmp/x`, `2>/tmp/err`, `&>/tmp/x`.
# Redirect operators inside quotes are ignored (see mask_quoted_redirect_ops).
has_redirect_to_drive_root_tmp() {
  local s
  s=$(mask_quoted_redirect_ops "$1")
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

# Split a (already lowercased, slash-normalized) command on unquoted shell
# control operators so `mkdir ./out && cat /tmp/x` is inspected per segment.
# Emits NUL-terminated segments on stdout.
split_shell_segments() {
  local s="$1" out="" i=0 c quote="" nex
  local -i len=${#s}
  while ((i < len)); do
    c="${s:i:1}"
    if [[ -n "$quote" ]]; then
      if [[ "$c" == "$quote" ]]; then
        quote=""
      fi
      out+="$c"
      i=$((i + 1))
      continue
    fi
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      quote="$c"
      out+="$c"
      i=$((i + 1))
      continue
    fi
    # Control operators: ; | & and digraphs && ||
    if [[ "$c" == ';' || "$c" == '|' || "$c" == '&' ]]; then
      printf '%s\0' "$out"
      out=""
      nex="${s:i+1:1}"
      if [[ ( "$c" == '&' || "$c" == '|' ) && "$nex" == "$c" ]]; then
        i=$((i + 2))
      else
        i=$((i + 1))
      fi
      continue
    fi
    out+="$c"
    i=$((i + 1))
  done
  printf '%s\0' "$out"
}

# Last non-option token of a utility segment — the usual destination for cp/mv
# and Copy-Item/Move-Item. Flags of the form -x / --long are skipped; a flag
# that consumes a path (-t / --target-directory / -destination) treats the next
# token as the destination immediately.
segment_destination_operand() {
  local subject="$1" tok dest="" expect_dest=0
  local -a tokens=()
  # Intentional word-split of the static matcher subject into tokens.
  # shellcheck disable=SC2206
  tokens=( $subject )
  for tok in "${tokens[@]}"; do
    tok="${tok#\'}"
    tok="${tok%\'}"
    tok="${tok#\"}"
    tok="${tok%\"}"
    if ((expect_dest)); then
      dest="$tok"
      expect_dest=0
      continue
    fi
    case "$tok" in
    -t | --target-directory | --target-directory=* | -destination | -destination:* | -dest | -dest:*)
      if [[ "$tok" == *=* || "$tok" == *:* ]]; then
        dest="${tok#*=}"
        dest="${dest#*:}"
      else
        expect_dest=1
      fi
      ;;
    -*)
      continue
      ;;
    tee | mktemp | mkdir | touch | install | cp | mv | dd | install.exe | tee.exe | \
    set-content | add-content | out-file | tee-object | new-item | export-clixml | \
    export-csv | copy-item | move-item | copy | move | cpi | mi | ac | ni)
      # command word — skip
      ;;
    *)
      dest="$tok"
      ;;
    esac
  done
  printf '%s' "$dest"
}

# True when a segment's destination-shaped operand is a drive-root tmp path.
# Creators (mkdir/touch/…) treat any drive-root path argument as a write;
# copy/move utilities bind only the destination operand.
segment_writes_drive_root_tmp() {
  local subject="$1" dest
  # Creators / content writers: any drive-root tmp path in the segment is a write.
  if [[ "$subject" =~ (^|[[:space:]])(tee|mktemp|mkdir|touch|dd|tee\.exe)([[:space:]]|$) ]] ||
    [[ "$subject" =~ (^|[[:space:];|&]|/)(set-content|add-content|out-file|tee-object|new-item|export-clixml|export-csv)([[:space:]]|:|$) ]] ||
    [[ "$subject" =~ (^|[[:space:]])(ac|ni)([[:space:]]|$) ]]; then
    has_drive_root_tmp "$subject" && return 0
    return 1
  fi
  # Copy / move / install: destination operand only (avoids `cp /tmp/src ./dst`).
  if [[ "$subject" =~ (^|[[:space:]])(cp|mv|install|install\.exe|copy-item|move-item|copy|move|cpi|mi)([[:space:]]|$) ]]; then
    dest=$(segment_destination_operand "$subject")
    [[ -n "$dest" ]] || return 1
    has_drive_root_tmp "$dest" && return 0
    return 1
  fi
  # Inline python write opening a drive-root tmp path
  if [[ "$subject" =~ (open|write_text|write_bytes|makedirs)\( ]] &&
    [[ "$subject" =~ (\/tmp|\/[a-z]\/tmp|[a-z]:\/tmp) ]]; then
    return 0
  fi
  return 1
}

# Write-shaped signal: a known producer / destination utility whose write
# target is a drive-root tmp path. Echo/printf alone are NOT enough (they write
# stdout, and a prose mention of /tmp must stay allowed). Compound commands are
# inspected per segment so `mkdir ./out && cat /tmp/src` stays allowed.
has_write_utility_with_drive_root_tmp() {
  local s="$1" piece
  has_drive_root_tmp "$s" || return 1
  while IFS= read -r -d '' piece; do
    [[ -n "${piece//[[:space:]]/}" ]] || continue
    if segment_writes_drive_root_tmp "$piece"; then
      return 0
    fi
  done < <(split_shell_segments "$s")
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
