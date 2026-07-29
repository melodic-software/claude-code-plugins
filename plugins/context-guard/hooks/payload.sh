#!/usr/bin/env bash
# context-guard-local stdin reader for hook payloads.
#
# The shared lib's hook::buffer_stdin performs ONE bounded read, which on
# Windows/MSYS pipes (~40KB/s byte-at-a-time delivery) times out on exactly
# the payloads these hooks exist for — PostCompact carries the full
# compact_summary, PreToolUse carries the full Write content, PostToolBatch
# carries every serialized tool result (measured: ~80KB payloads already
# lost). This reader mirrors statusline-tee.sh's proven drain loop: read -N
# buffers in 1MiB blocks until EOF with a per-block 5s timeout, so a stalled
# pipe is still bounded while a large healthy payload arrives whole. Bash
# below 4.1 (macOS ships 3.2) lacks -N and falls back to the delimiter form,
# which already reads to EOF fast on native POSIX pipes.
#
# Returns 1 on an empty payload; callers fail open on that. On a stalled
# pipe the caller sees a truncated payload whose regex/jq extraction then
# fails its own validation — never a fabricated value.

cg::read_payload() {
  local input="" chunk=""
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
    while IFS= read -r -N 1048576 -t 5 chunk; do
      input+="$chunk"
      chunk=""
    done
    input+="$chunk" # EOF/timeout leaves the final partial block in chunk
  else
    IFS= read -r -d '' -t 5 input || true
  fi
  input=${input//$'\r'/}
  [[ -n "$input" ]] || return 1
  printf '%s' "$input"
}
