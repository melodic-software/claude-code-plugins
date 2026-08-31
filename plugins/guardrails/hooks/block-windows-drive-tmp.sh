#!/usr/bin/env bash
# PreToolUse hook: block writes whose target is a Windows drive-root temp path.
# Triggered on Bash and PowerShell tool calls (a command string), and on
# Write / Edit / MultiEdit / NotebookEdit tool calls (a file path).
#
# TWO DOORS, ONE MATCHER. A write reaches the drive root through either shape,
# and until 0.30.0 only the command shape was inspected: the hook read
# `.tool_input.command`, a `Write` payload carries `file_path` instead, so the
# empty-COMMAND early exit returned before any matcher ran and an empty
# `C:\tmp\tmp.rSFIkHm5DO` was created with no guard noticing. Both doors now feed
# the SAME has_drive_root_tmp() matcher. The file-path lane needs none of the
# command lane's inference — no redirect parsing, no write-utility whitelist,
# no segment splitting — because on Write/Edit the path IS the write target.
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
# SIBLING GUARD, DISJOINT SCOPE. block-exported-msys-pathconv.sh guards the same
# family (drive-root residue on Windows) through a different door: it matches an
# EXPORTED MSYS_NO_PATHCONV / MSYS2_ARG_CONV_EXCL, with no path component at all,
# because #2870's incident command carried a path argument textually identical to
# one that had already worked — the discriminator was the environment, not the
# string. This guard would not fire on that; that guard would not fire on any
# case here. Two hooks rather than one overloaded matcher is deliberate.
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

# Path fields only — never `.tool_input.content` / `.new_string` / `.new_source`.
# HOOK_JQ_FIELDS_NUL is computed across every REQUESTED field, so pulling the
# written CONTENT in here would make this guard block on a NUL anywhere in a
# file body: a false-positive class that is hardcoded-path-check's concern, not
# this guard's. `notebook_path` rides along in the same jq process (one spawn,
# not two) because NotebookEdit spells its target differently from Write/Edit.
jq_rc=0
hook::jq_fields "$INPUT" \
  '.tool_input.command' '.tool_name' \
  '.tool_input.file_path' '.tool_input.notebook_path' || jq_rc=$?
if ((jq_rc == 2)); then
  echo "BLOCKED: the hook payload could not be parsed." >&2
  exit 2
fi
((jq_rc != 0)) && exit 0

# A NUL byte in EITHER field is fail-CLOSED (#2136 / #2122).
if ((HOOK_JQ_FIELDS_NUL)); then
  echo "BLOCKED: the payload carries a NUL byte, which neither a command nor a file path can reliably carry." >&2
  echo "What a guard can read is not dependably what would run, so this is refused rather than matched." >&2
  echo "Fix: reissue the tool call without the embedded NUL." >&2
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
# Write / Edit / MultiEdit spell the target `file_path`; NotebookEdit spells it
# `notebook_path`. Reading both and taking whichever is populated keeps the lane
# correct without depending on which spelling a given tool version emits.
FILE_PATH="${HOOK_JQ_FIELDS[2]:-}"
[[ -n "$FILE_PATH" ]] || FILE_PATH="${HOOK_JQ_FIELDS[3]:-}"

# Neither door carried anything to inspect. Before 0.30.0 this exit tested
# COMMAND alone, which is exactly how a `Write` payload passed unexamined.
[[ -n "$COMMAND" || -n "$FILE_PATH" ]] || exit 0

# Non-Windows hosts: /tmp is the real POSIX temp. Skip entirely. Tests force
# OSTYPE=msys to exercise the Windows lane on Linux CI.
case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*) exit 0 ;;
esac

MAX_COMMAND_LEN=16384

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  # Resolved HERE, not at top level: hook::extract_bash_subject runs in a
  # command substitution, and that fork was being paid on every tool call even
  # when no telemetry sink is wired — which is the default, and now on the
  # per-Write surface too, where the helper returns the bare tool name and the
  # fork buys a constant. Same shape as the plugin's other lazily-resolved
  # telemetry fields.
  local SUBJECT data
  SUBJECT=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")
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
# other argv-faithful Bash guards). The ceiling exists because the COMMAND lane
# below walks the string character by character twice (mask_quoted_redirect_ops,
# split_shell_segments) before it matches anything. NO EQUIVALENT CEILING GUARDS
# THE FILE-PATH LANE, and that is a decision rather than an omission: that lane
# runs three EREs against one string with no tokenization, so length buys no
# parse ambiguity there, and detection does not degrade with length — a
# drive-root prefix matches at any total length. A blocking ceiling would only
# add a false-positive class (a legitimate long path refused for its size). The
# payload as a whole is still bounded upstream by hook::buffer_stdin's idle
# timeout, which fails CLOSED on a truncated read.
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  block "too-long"
fi

# Slash-normalize so C:\tmp, C:/tmp, and \tmp share one matcher. Lowercase for
# case-insensitive Windows path compare without relying on bash [[ =~ ]] flags.
# Pure shell, no `printf | tr`: that pipeline is a fork AND an exec (~280 ms
# together on Windows Git Bash) to fold one character class, and this guard now
# fires on the per-Write surface as well, where that pair would be pure added
# budget. Same bytes for ASCII paths and commands, which is all a drive-root
# matcher reads. Result lands in NORM_OUT rather than on stdout because a
# command substitution would fork the shell right back.
norm_lower() {
  local s="${1//\\//}"
  NORM_OUT="${s,,}"
}

norm_lower "$COMMAND"
NORM="$NORM_OUT"

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
  # MSYS /<drive>/tmp, in two arms because a `:` on the left is ambiguous and
  # the two readings decide oppositely.
  #
  # A DRIVE COLON must NOT satisfy the boundary: after slash-normalization
  # `D:\a\tmp\x` reads as `d:` + `/a/tmp`, and that is an ordinary `tmp`
  # directory two levels down, not a drive root. Blocking it was a FALSE
  # POSITIVE that predates the file-path lane (the command lane blocked
  # `mkdir -p D:\a\tmp\x` too), and it made the guard contradict its own
  # premise, since the identical MSYS spelling `/d/a/tmp/x` was allowed — one
  # sink deciding two ways. The lane makes it reachable from every Write/Edit,
  # so it is fixed here rather than inherited.
  #
  # A PARAMETER COLON must still satisfy it. `-Path:` / `-FilePath:` /
  # `-Destination:` is valid PowerShell binding, so `Set-Content -Path:/c/tmp/x`
  # is a real drive-root write and one of its space-bound twins is a pinned
  # MUST-fire case. Excluding `:` outright would have dropped that whole class.
  #
  # The discriminator is what sits before the colon. A DRIVE SPEC is exactly one
  # alphanumeric at a word boundary — `D:`, ` D:`, `"D:`, `(D:` — so arm 2
  # excludes only that shape and takes every other colon, which is the narrowest
  # change that fixes the false positive. Its three alternatives are: a
  # non-alphanumeric immediately before the colon (`;:`, `":`, `):` — never a
  # drive spec); two alphanumerics (a multi-character token such as `-Path:` or
  # `host:`); and a single alphanumeric behind a flag dash (`-t:`).
  #
  # Two accepted residuals, both unchanged from before the fix rather than
  # introduced by it. A PATH-style list (`PATH=/usr/bin:/c/tmp cmd`) presents
  # the multi-character-token shape and still matches, so a command whose write
  # target is elsewhere can be matched over a search-path entry — lexically
  # indistinguishable from a bound parameter. And a remote spec with a
  # single-letter host (`ssh u@h:/c/tmp/x`) now reads as a drive spec and is not
  # matched; it names a path on another machine, which this guard never governed.
  if [[ "$s" =~ (^|[^[:alnum:]._/:])\/[a-z]\/tmp(\/|[^[:alnum:]_./-]|$) ]]; then
    return 0
  fi
  if [[ "$s" =~ ([^[:alnum:]]|[[:alnum:]][[:alnum:]]|-[[:alnum:]]):\/[a-z]\/tmp(\/|[^[:alnum:]_./-]|$) ]]; then
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

# --- File-path lane: Write / Edit / MultiEdit / NotebookEdit -----------------
# On these tools the payload's path IS the write target, so the whole
# write-shape inference the command lane needs — redirect parsing, the producer
# utility whitelist, per-segment splitting — is structurally absent here. The
# matcher is the shipped has_drive_root_tmp(), unchanged and unduplicated, so
# every spelling the command lane blocks (POSIX /tmp, MSYS /c/tmp, C:\tmp,
# drive-root \tmp) and every one it permits (%TEMP% expansions, /var/tmp,
# ./tmp, foo/tmp) decide identically on this lane.
if [[ -n "$FILE_PATH" ]]; then
  norm_lower "$FILE_PATH"
  if has_drive_root_tmp "$NORM_OUT"; then
    block "file-path"
  fi
fi

# --- Command lane: Bash / PowerShell -----------------------------------------
# Skipped outright on a file-path payload: has_redirect_to_drive_root_tmp runs
# mask_quoted_redirect_ops in a command substitution, and forking the shell to
# scan an empty string would be per-Write budget spent to reach a foregone `no`.
if [[ -n "$COMMAND" ]]; then
  if has_redirect_to_drive_root_tmp "$NORM"; then
    block "redirect"
  fi

  if has_write_utility_with_drive_root_tmp "$NORM"; then
    block "write-utility"
  fi
fi

emit_tel "ok" ""
exit 0
