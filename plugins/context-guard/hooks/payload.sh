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

# Every local here carries a `__cg_` prefix, including the accumulator and the
# read block. `printf -v "$__cg_dest"` resolves the destination name against
# THIS function's scope, so a local sharing a caller's chosen destination name
# would be assigned instead of the caller's variable, and the function would
# still return 0 — the caller sees success and an unset variable. The header
# above invites new callers to adopt the `_to` form, and `input` and `chunk`
# are the names such a caller reaches for first, so they must not be locals.
# Same reasoning, same prefix convention as `__hu_` in lib/hook-utils.sh.
cg::read_payload_to() {
  local __cg_dest="$1"
  # The prefix reserves a namespace, it does not abolish the hazard: these three
  # names are this function's own locals, so `printf -v` would land on one of
  # them instead of the caller's variable. Refuse loudly rather than returning 0
  # with the caller's variable unset, which is the failure mode that makes this
  # class of bug hard to see. Only these three are reserved; `__cg_buf`, which
  # the cg::read_payload wrapper below passes, is deliberately not among them.
  case $__cg_dest in
    __cg_dest | __cg_input | __cg_chunk)
      printf 'cg::read_payload_to: destination %s is a reserved internal name\n' \
        "$__cg_dest" >&2
      return 2
      ;;
    *) ;; # every other name is the caller's to choose
  esac
  local __cg_input="" __cg_chunk=""
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
    while IFS= read -r -N 1048576 -t 5 __cg_chunk; do
      __cg_input+="$__cg_chunk"
      __cg_chunk=""
    done
    __cg_input+="$__cg_chunk" # EOF/timeout leaves the final partial block in __cg_chunk
  else
    IFS= read -r -d '' -t 5 __cg_input || true
  fi
  __cg_input=${__cg_input//$'\r'/}
  [[ -n "$__cg_input" ]] || return 1
  # `printf -v`, not a `local -n` nameref: namerefs arrived in bash 4.3 and
  # these scripts support the 3.2 macOS ships — the same support floor the -N
  # fallback above exists for.
  printf -v "$__cg_dest" '%s' "$__cg_input"
}

cg::read_payload() {
  local __cg_buf=""
  cg::read_payload_to __cg_buf || return 1
  printf '%s' "$__cg_buf"
}
