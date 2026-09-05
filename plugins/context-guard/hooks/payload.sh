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
#
# TWO ENTRY POINTS, ONE DRAIN LOOP. `cg::read_payload_to <varname>` assigns the
# payload to the named variable in the CALLER's process; `cg::read_payload`
# prints it, which every caller then has to wrap in `$(...)` — a command
# substitution, and so a forked subshell paid on the critical path of every
# fire. On a host where process creation costs hundreds of milliseconds (#3508)
# that fork is the entire cost of reading stdin, because the drain loop itself
# is nothing but `read` builtins. New callers take the `_to` form; the printing
# form stays for the callers that still use it and delegates to `_to` rather
# than duplicating the loop, so there is one drain implementation to change.
#
# WHY NOT HAND THE HOOK'S STDIN STRAIGHT TO `jq` and skip this file on the hot
# path. It would not save a process: via `_to` the loop is `read` builtins and
# costs zero. What it would save is the `<<<` here-string the caller then needs
# to re-feed the payload, which bash spills to a temp file at or above 64KiB
# (see zone-crossing-inject.sh's payload-pass note). The loop is kept anyway,
# because the bounded `read -t 5` below is the property that caps a stalled
# pipe: a slow reader truncates at five seconds instead of blocking to the
# harness timeout, which is the exact symptom #3508 is about. Disk I/O on
# oversized payloads is the smaller cost of the two.

cg::read_payload_to() {
  local __cg_dest="$1"
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
  # `printf -v`, not a `local -n` nameref: namerefs arrived in bash 4.3 and
  # these scripts support the 3.2 macOS ships — the same support floor the -N
  # fallback above exists for.
  printf -v "$__cg_dest" '%s' "$input"
}

cg::read_payload() {
  local __cg_buf=""
  cg::read_payload_to __cg_buf || return 1
  printf '%s' "$__cg_buf"
}
