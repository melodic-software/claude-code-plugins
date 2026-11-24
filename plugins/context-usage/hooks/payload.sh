#!/usr/bin/env bash
# context-usage-local stdin reader for hook payloads.
#
# The shared lib's hook::buffer_stdin performs ONE bounded read, which on
# Windows/MSYS pipes (~40KB/s byte-at-a-time delivery) times out on exactly
# the payloads these hooks exist for — PostCompact carries the full
# compact_summary (measured: ~80KB payloads already lost). This reader's
# drain loop: read -N buffers in 1MiB blocks until EOF with a per-block 5s
# timeout, so a stalled pipe is still bounded while a large healthy payload
# arrives whole. Bash
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
cg::read_payload_to() {
  local __cg_dest="$1"
  case $__cg_dest in
    __cg_dest | __cg_input | __cg_chunk)
      printf 'cg::read_payload_to: destination %s is a reserved internal name\n' \
        "$__cg_dest" >&2
      return 2
      ;;
    *) ;;
  esac
  local __cg_input="" __cg_chunk=""
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
    while IFS= read -r -N 1048576 -t 5 __cg_chunk; do
      __cg_input+="$__cg_chunk"
      __cg_chunk=""
    done
    __cg_input+="$__cg_chunk"
  else
    IFS= read -r -d '' -t 5 __cg_input || true
  fi
  __cg_input=${__cg_input//$'\r'/}
  [[ -n "$__cg_input" ]] || return 1
  printf -v "$__cg_dest" '%s' "$__cg_input"
}

cg::read_payload() {
  local __cg_buf=""
  cg::read_payload_to __cg_buf || return 1
  printf '%s' "$__cg_buf"
}
