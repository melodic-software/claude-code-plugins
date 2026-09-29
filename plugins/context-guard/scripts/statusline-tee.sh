#!/usr/bin/env bash
# statusline-tee: transparent statusline wrapper that tees each session's
# context-window fields to a per-session snapshot file.
#
# SHELL REQUIREMENT: Bash. The statusline `command` runs in a shell; on
# Windows this script requires Git Bash (bash.exe from Git for Windows), so
# the wiring invokes it explicitly as
#   bash "<plugin-root>/scripts/statusline-tee.sh" [wrapped-command...]
# The setup skill (/context-guard:setup check) prints the exact
# settings.json edit with the resolved path.
#
# Usage:
#   statusline-tee.sh <command> [args...]  Wrap an existing statusline command:
#                                          the stdin JSON passes through to it
#                                          and its stdout and exit code are the
#                                          statusline's, byte-for-byte.
#   statusline-tee.sh                      No statusline configured: act as a
#                                          standalone minimal statusline
#                                          (model + context usage).
#
# Tee contract (../reference/reader-contract.md is the authoritative reader
# side): a refresh writes
#   ~/.claude/context-guard/context/<session_id>.json
# whenever the body below changed, and at least once per no-change floor
# (CG_TEE_NOCHANGE_FLOOR, 60 s) while it did not (see PROCESS BUDGET)
# — one JSON object with captured_at (ISO-8601 UTC), session_id, cli_version
# (the payload's top-level `version`, when present — it gates the reader's
# token shape) and, when present on stdin, the context_window object copied
# VERBATIM (field
# additions upstream flow through without a plugin change; null fields are
# the reader's concern). The path is deliberately HOME-anchored and outside
# ${CLAUDE_PLUGIN_DATA}: it is a documented cross-plugin artifact seam that
# sibling-plugin sessions read, PER-SESSION by design (no last-writer-wins
# collapse across sessions).
#
# PATH CONTAINMENT: session_id is used as a filename, so it is accepted only
# when it matches ^[A-Za-z0-9_-]+$ — anything else (absent, path separators,
# dots, spaces) skips the tee entirely for that refresh. The wrapped
# statusline is unaffected.
#
# PRUNING (implementation detail, not contract): sibling *.json snapshots
# older than 14 days, and their last-write records, are deleted by a write
# at most once an hour. The cutoff is deliberately far
# larger than the reader contract's 10-minute staleness window so a
# live-but-idle session's snapshot is never deleted, and in-flight
# .tmp.* files are never touched by the prune (aged temp ORPHANS are the
# reclaim sweep's job — see TEMP-FILE RECLAIM below).
#
# TEMP-FILE RECLAIM: a temp file can outlive this process. Claude Code
# "cancels the in-flight script" when a new update arrives while this one is
# still running (https://code.claude.com/docs/en/statusline), and a
# cancellation between the write and the rename leaves the temp behind — no
# failed rm is needed to explain it, the process simply never reaches the
# reclaim line. Two mechanisms, because neither is sufficient alone: a trap
# reclaims on exit and on a catch-able signal, and an age-filtered sweep of
# leftover siblings recovers what a SIGKILL, a crash, or power loss leaves,
# which no trap can. The sweep costs nothing on a clean directory — a glob
# decides whether to spawn anything at all — and it cannot race a live
# sibling, since the normal write-to-rename window is sub-second while the
# age floor is a minute.
#
# ATOMICITY: concurrent refreshes of the same session and cross-session
# sibling writes share one directory, and readers must never see torn JSON,
# so the snapshot is written to a process-unique temp file in the same
# directory and renamed over the target. The temp file takes the inherited
# umask; the owner-only directory is the access boundary. On Windows, renaming over a target
# another process holds open can fail EACCES (no FILE_SHARE_DELETE), so the
# rename is retried briefly and then SKIPPED — the next refresh supersedes a
# skipped snapshot within seconds, so the skip is quiet by design (the
# durable visibility surface for a persistently broken tee is the setup
# skill's freshness probe). No tee outcome — missing jq, unwritable path,
# failed rename — ever alters the wrapped statusline's output or exit code.
#
# jq is required for the tee and for the standalone line; when absent the
# wrapper stays transparent and appends a visible one-line notice instead of
# silently dropping the feature.

set -uo pipefail

INPUT=""
# Time-bounded buffered read of the whole stdin payload (Win32 pipes can
# stall before EOF; a truncated payload just fails jq below and tees nothing
# this refresh). read -N buffers in 1MiB blocks and the loop drains until
# EOF, so the wrapped command receives EVERY byte regardless of payload size
# — the block size matters on Windows/MSYS pipes where the -d '' byte-at-a-
# time loop moves ~40KB/s (measured on Git Bash), and the per-block -t 5
# timeout bounds a stalled pipe without capping a large healthy payload.
# Bash below 4.1 (macOS ships 3.2) lacks -N and falls back to the delimiter
# form, which already reads to EOF, fast enough on native POSIX pipes.
# Documented boundary: on a stalled pipe (timeout mid-payload) the wrapped
# command receives only the drained bytes and fails with its own exit code;
# the tee silently skips that refresh (jq rejects the truncated JSON).
if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
  _chunk=""
  while IFS= read -r -N 1048576 -t 5 _chunk; do
    INPUT+="$_chunk"
    _chunk=""
  done
  INPUT+="$_chunk" # EOF/timeout leaves the final partial block in _chunk
else
  IFS= read -r -d '' -t 5 INPUT || true
fi

# Path of the temp file currently in flight, for the reclaim traps below. A
# global rather than the function's local: the trap body is evaluated when the
# trap fires, by which time the function's locals are gone.
TEE_TMP=""

reclaim_tee_tmp() {
  [[ -n "$TEE_TMP" ]] && rm -f "$TEE_TMP" 2>/dev/null
  TEE_TMP=""
  return 0
}

# The signal traps exit rather than reclaiming directly, so the EXIT trap stays
# the single reclaim path. Exiting is also the right response to a cancelling
# signal: this refresh's snapshot is already superseded by the update that
# cancelled it.
trap 'reclaim_tee_tmp' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

# Reclaim temp siblings left by a process that never got to clean up. Only
# files older than the age floor are touched, so a concurrent refresh's live
# temp — sub-second between write and rename — is never a candidate.
#
# The glob runs first and decides whether to spawn at all: on a clean
# directory, which is every refresh in normal operation, this costs zero
# processes. The pattern requires the .json.tmp. infix, so it can never match
# a snapshot the prune owns, and the prune's *.json pattern never matches
# these dot-prefixed names — the two mechanisms are disjoint by construction.
sweep_stale_tee_temps() {
  local dir="$1" candidate
  for candidate in "$dir"/.*.json.tmp.*; do
    [[ -e "$candidate" ]] || continue
    find "$dir" -maxdepth 1 -type f -name '.*.json.tmp.*' \
      -mmin +1 -exec rm -f {} + 2>/dev/null || true
    return 0
  done
  return 0
}

# PROCESS BUDGET. This runs on every statusline render, and on Windows every
# process creation costs tens of milliseconds, so the render path is builtins:
#   - unchanged render: the payload's snapshot body equals the one this session
#     last wrote, less than CG_TEE_NOCHANGE_FLOOR seconds ago (default 60, a
#     tenth of the reader contract's 10-minute staleness window), and the
#     target is still the file that write produced. Nothing is written and no
#     process starts.
#   - writing render: one process, the atomic `mv`.
#   - once an hour (behind .prune-stamp), the retention prune adds a `find`
#     and re-asserts the directory mode.
# The body comes from cg_body_builtin; a payload it cannot prove (larger than
# 64 KiB, not a plain object, a session id or version that needs escaping, a
# context_window holding anything but plain keys, strings, numbers and
# literals) goes to jq, exactly as before. Below bash 4.2, where %(...)T does
# not exist, timestamps come from `date` and the no-change floor and the prune
# interval are off, so every render writes and prunes, as before.

# Set by cg_body_builtin: the snapshot body after its captured_at member, and
# the session id.
_CG_BODY=""
_CG_SID=""
_CG_PARTS=()

# Succeed when <text>, whitespace already removed outside strings and every
# string replaced by `s`, is one JSON value by the JSON grammar, with numbers
# limited to the spellings every jq version prints back unchanged: at most 15
# integer digits, no trailing fraction zero, no exponent (jq 1.7 prints -3e2
# as -3E+2, jq 1.6 as -300). The same
# whole-string reduction hook-utils.sh uses: scalars and strings become `v`, a
# key stays `s`, then `s:v` is a member `m`, `v,v` and `m,m` fold, and `{m}`,
# `{}`, `[v]`, `[]` are values, until the text is `v` or stops changing.
cg_json_value_ok() {
  local g="$1" prev sc
  sc=${g//[][\{\}:,]/ }
  local scre='^ *((s|true|false|null|-?(0|[1-9][0-9]{0,14})(\.[0-9]{0,14}[1-9])?) +)*$'
  [[ "$sc " =~ $scre ]] || return 1
  g=${g//s:/k:}
  g=${g//[^\]\[\{\}:,k]/v}
  while [[ "$g" == *vv* ]]; do g=${g//vv/v}; done
  g=${g//k:/s:}
  while :; do
    prev=$g
    g=${g//s:v/m}
    while [[ "$g" == *v,v* ]]; do g=${g//v,v/v}; done
    while [[ "$g" == *m,m* ]]; do g=${g//m,m/m}; done
    g=${g//\{m\}/v}
    g=${g//\{\}/v}
    g=${g//\[v\]/v}
    g=${g//\[\]/v}
    [[ "$g" != "$prev" ]] || break
  done
  [[ "$g" == v ]]
}

# Build _CG_BODY and _CG_SID from $INPUT with builtins, byte-identical to what
# the jq program in tee_snapshot prints for the same payload. Returns 1
# whenever that cannot be proven, and the caller asks jq.
#
# The payload is split at every unescaped double quote, after replacing each
# `\\` and `\"` pair with the same-length `@@`, so even parts are structural
# text and odd parts are string bodies, and an offset into the neutralized
# text is the same offset into the payload. Depth is counted in structural
# parts only, so a brace inside a string never moves it, and only a key at
# depth 1 of the root object is read. Duplicate root keys resolve to the last
# one, as in jq.
cg_body_builtin() {
  local s="$INPUT" t q n i part np after sid="" sid_seen=0 ver="" ver_seen=0 cw="" cw_seen=0
  local depth=0 off=0 o c glob_was_on=0
  ((${#s} <= 65536)) || return 1
  t=${s//"\\\\"/@@}
  t=${t//"\\\""/@@}
  q=${t//\"/}
  n=$((${#t} - ${#q}))
  ((n % 2 == 0 && n <= 4000)) || return 1
  [[ $- == *f* ]] || glob_was_on=1
  set -f
  local IFS='"'
  # shellcheck disable=SC2206 # splitting on IFS='"' is the whole point
  _CG_PARTS=($t)
  IFS=$' \t\n'
  ((glob_was_on)) && set +f
  n=${#_CG_PARTS[@]}
  ((n % 2 == 1)) || return 1
  part=${_CG_PARTS[0]}
  part=${part#"${part%%[![:space:]]*}"}
  [[ "$part" == \{* ]] || return 1
  part=${_CG_PARTS[n - 1]}
  part=${part%"${part##*[![:space:]]}"}
  [[ "$part" == *\} ]] || return 1

  for ((i = 0; i < n; i++)); do
    part=${_CG_PARTS[i]}
    if ((i % 2 == 0)); then
      o=${part//[^\{\[]/}
      c=${part//[^\}\]]/}
      depth=$((depth + ${#o} - ${#c}))
      ((depth > 0 || i == n - 1)) || return 1
      off=$((off + ${#part} + 1))
      continue
    fi
    if ((depth != 1)) || [[ "$part" != session_id && "$part" != version && "$part" != context_window ]]; then
      off=$((off + ${#part} + 1))
      continue
    fi
    np=${_CG_PARTS[i + 1]}
    np=${np#"${np%%[![:space:]]*}"}
    if [[ "$np" != :* ]]; then
      off=$((off + ${#part} + 1))
      continue
    fi
    after=${np#:}
    after=${after#"${after%%[![:space:]]*}"}
    local key="$part" vstart=$((off + ${#part} + 1 + ${#_CG_PARTS[i + 1]} - ${#after}))
    off=$((off + ${#part} + 1))
    case "$key" in
    session_id)
      # A string value is the next odd part; anything else is jq's to judge.
      [[ -z "$after" ]] && ((i + 2 < n)) || return 1
      [[ "${_CG_PARTS[i + 2]}" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
      sid=${_CG_PARTS[i + 2]}
      sid_seen=1
      ;;
    version)
      if [[ -z "$after" ]]; then
        ((i + 2 < n)) || return 1
        [[ "${_CG_PARTS[i + 2]}" =~ ^[A-Za-z0-9._+-]*$ ]] || return 1
        ver=${_CG_PARTS[i + 2]}
        ver_seen=1
      else
        # Not a string: jq copies no cli_version.
        ver_seen=0
      fi
      ;;
    context_window)
      [[ -n "$after" ]] || return 1
      cg_slice_value "$t" "$vstart" || return 1
      cw=$_CG_SLICE
      cw_seen=1
      ;;
    *) ;;
    esac
  done
  ((depth == 0 && sid_seen)) || return 1
  _CG_SID=$sid
  _CG_BODY="\"session_id\":\"$sid\""
  ((ver_seen)) && _CG_BODY+=",\"cli_version\":\"$ver\""
  ((cw_seen)) && _CG_BODY+=",\"context_window\":$cw"
  return 0
}

# Set _CG_SLICE to the compact form of the JSON value starting at offset $2 of
# the neutralized text $1: whitespace outside strings removed, as `jq -c`
# prints it. Returns 1 unless the value is an object, array or scalar whose
# strings hold only [A-Za-z0-9 _.:/+-] (printed by jq exactly as read) and
# which passes cg_json_value_ok, number spellings included.
_CG_SLICE=""
cg_slice_value() {
  local t="$1" pos="$2" ch rest body d=0 out="" skel="" limit=$(($2 + 4096)) len=${#1}
  ch=${t:pos:1}
  if [[ "$ch" != [\{\[] ]]; then
    rest=${t:pos:64}
    rest=${rest%%[],\}[:space:]]*}
    [[ "$rest" =~ ^(true|false|null|-?(0|[1-9][0-9]{0,14})(\.[0-9]{0,14}[1-9])?)$ ]] || return 1
    _CG_SLICE=$rest
    return 0
  fi
  while ((pos < len && pos < limit)); do
    ch=${t:pos:1}
    case "$ch" in
    '"')
      rest=${t:pos+1:limit-pos}
      [[ "$rest" == *\"* ]] || return 1
      body=${rest%%\"*}
      [[ "$body" =~ ^[A-Za-z0-9\ _.:/+-]*$ ]] || return 1
      out+="\"$body\""
      skel+=s
      pos=$((pos + ${#body} + 2))
      continue
      ;;
    [\{\[]) d=$((d + 1)) ;;
    [\}\]]) d=$((d - 1)) ;;
    [[:space:]])
      pos=$((pos + 1))
      continue
      ;;
    *) ;;
    esac
    out+=$ch
    skel+=$ch
    pos=$((pos + 1))
    ((d == 0)) && break
  done
  ((d == 0)) || return 1
  cg_json_value_ok "$skel" || return 1
  _CG_SLICE=$out
  return 0
}

# Epoch seconds into _CG_NOW, or empty below bash 4.2.
_CG_NOW=""
cg_set_now() {
  _CG_NOW=""
  ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))) || return 1
  printf -v _CG_NOW '%(%s)T' -1 2>/dev/null || _CG_NOW=""
  [[ "$_CG_NOW" =~ ^[0-9]+$ ]] || {
    _CG_NOW=""
    return 1
  }
  return 0
}

# Read an epoch-second stamp file's first line into the named variable, or 0
# when it is absent, unreadable or not a plain integer. The validation matters:
# bash evaluates the TEXT of an arithmetic operand, so a stamp shaped like
# `a[$(cmd)]` would run cmd.
cg_read_stamp() {
  local _val=0
  if [[ -f "$2" ]]; then
    IFS= read -r _val 2>/dev/null <"$2" || true
    [[ "$_val" =~ ^[0-9]+$ ]] || _val=0
  fi
  printf -v "$1" '%s' "$_val"
}

# Write one per-session contract snapshot. Every failure path returns 0: the
# tee must never propagate into the statusline pipeline.
tee_snapshot() {
  [[ -n "${HOME:-}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0 # visible notice emitted by the caller

  local ts="" now="" body="" sid="" out
  cg_set_now && now=$_CG_NOW

  # The builtin reader walks bytes: the C locale makes every length and offset
  # a byte count and every [A-Za-z0-9] range ASCII. The caller's LC_ALL is put
  # back before anything else runs, since the wrapped statusline inherits it.
  # An empty now (bash below 4.2, or a failed printf %()T) skips the reader:
  # its byte-for-byte match with jq is proven on bash 5.x only, so those hosts
  # take the body from jq.
  local lc_set=${LC_ALL+x} lc_was=${LC_ALL-} built=1
  LC_ALL=C
  if [[ -z "$now" || -n "${CG_TEE_FORCE_JQ:-}" ]] || ! cg_body_builtin; then built=0; fi
  if [[ -n "$lc_set" ]]; then LC_ALL=$lc_was; else unset LC_ALL; fi

  if ((built)); then
    body=$_CG_BODY
    sid=$_CG_SID
  else
    # ONE jq pass for both the snapshot body and the session id. Framing is
    # payload-FIRST and is airtight because `jq -c` emits an object on exactly
    # one line (JSON escapes any newline inside a string), while a raw session
    # id may legally carry newlines: the first line is always the body,
    # everything after it is the id, and a multi-line id simply fails the
    # character-class gate below like any other bad value.
    #
    # cli_version carries the payload's top-level `version` (the Claude Code
    # version — statusline reference, verified 2026-08-10; the same re-check
    # confirms `total_input_tokens` / `total_output_tokens` are documented as
    # "tokens currently in the context window"). The reader needs it because
    # those fields mean current context occupancy only from 2.1.132 and were
    # CUMULATIVE session totals before it — a version floor the statusline page
    # NO LONGER states as of the 2026-08-10 re-check, so it is a retained claim
    # with no current upstream source; treat it as a lower bound, not doc-backed:
    # a cumulative total below the window size is indistinguishable from a real
    # occupancy, so without a version there is no sound way to trust the token
    # bands. Copied only when it is a string; absent leaves the reader on the
    # percentage shape alone.
    out=$(printf '%s' "$INPUT" | jq -rc '
      ({session_id: .session_id}
       + (if (.version? // null | type) == "string" then {cli_version: .version} else {} end)
       + (if has("context_window") then {context_window} else {} end)),
      (.session_id // "")
    ' 2>/dev/null) || return 0
    body=${out%%$'\n'*}
    # No second line at all (absent/null session_id) leaves sid empty, which
    # the character-class gate rejects — never the body text read as an id.
    [[ "$out" == *$'\n'* ]] && sid=${out#*$'\n'}
    [[ "$body" == \{*\} ]] || return 0
    body=${body#\{}
    body=${body%\}}
  fi
  [[ -n "$body" ]] || return 0

  # Sanitize the session id BEFORE any filesystem work: it becomes the
  # snapshot filename, so only [A-Za-z0-9_-] is accepted.
  [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || return 0

  local dir="$HOME/.claude/context-guard/context"
  local target="$dir/$sid.json"
  # The body and epoch of this session's last write. Implementation detail,
  # not contract: readers never open it, and the prune reaps it with its
  # snapshot.
  local last="$dir/.$sid.json.last"

  # Unchanged render: skip the write. The target must still be the file the
  # recorded write produced (not replaced since, which `-nt` would show, since
  # the record is written after the rename), and the record must be younger
  # than the floor, so an unchanged session's captured_at still advances once
  # per floor while it renders. A clock that went backwards writes.
  if [[ -n "$now" && -f "$target" && -f "$last" && ! -L "$last" && ! "$target" -nt "$last" ]]; then
    local floor="${CG_TEE_NOCHANGE_FLOOR:-60}" last_at="" last_body=""
    [[ "$floor" =~ ^[0-9]+$ ]] || floor=60
    { IFS= read -r last_at && IFS= read -r last_body; } 2>/dev/null <"$last" || true
    if [[ "$last_at" =~ ^[0-9]+$ && "$last_body" == "$body" ]] &&
      ((now >= last_at && now - last_at < floor)); then
      return 0
    fi
  fi

  if [[ -n "$now" ]]; then
    TZ=UTC printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' "$now" 2>/dev/null || ts=""
  fi
  if [[ -z "$ts" ]]; then
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || return 0
  fi

  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" 2>/dev/null || return 0
    # Owner-only contract dir: keeps other local users from pre-planting
    # symlinks or reading the snapshots. Best-effort (no-op on filesystems
    # without POSIX modes, e.g. Windows ACL volumes under Git Bash). The
    # hourly prune pass re-asserts it on a directory that already existed.
    chmod 700 "$dir" 2>/dev/null || true
  fi

  # Prune stale sibling snapshots (14 days ≫ the reader contract's 10-minute
  # staleness window — a live-but-idle session survives), with their
  # last-write records. Pattern *.json never matches the dot-prefixed .*.tmp.*
  # in-flight files; the explicit guard keeps it that way if the temp naming
  # ever changes. Each candidate's mtime is RE-CHECKED immediately before its
  # unlink (a sibling session can atomically replace its file between find's
  # scan and the delete); the residual microsecond race is accepted — a lost
  # snapshot is rewritten by that session's next statusline refresh and
  # readers fail open meanwhile. At most once an hour: .prune-stamp holds the
  # epoch of the last pass, and a missing, unreadable, future-dated or
  # symlinked stamp counts as due.
  local stamp="$dir/.prune-stamp" pruned_at=0
  cg_read_stamp pruned_at "$stamp"
  if [[ -z "$now" ]] || ((pruned_at > now || now - pruned_at >= 3600)); then
    if [[ -n "$now" && ! -L "$stamp" ]]; then
      printf '%s\n' "$now" 2>/dev/null >"$stamp" || true
    fi
    chmod 700 "$dir" 2>/dev/null || true
    find "$dir" -maxdepth 1 -type f \( \( -name '*.json' ! -name '.*' ! -name '*.tmp.*' \) -o -name '.*.json.last' \) \
      -mmin +20160 -exec sh -c '
        for f in "$@"; do
          [ -n "$(find "$f" -maxdepth 0 -mmin +20160 2>/dev/null)" ] && rm -f "$f"
        done' _ {} + 2>/dev/null || true
  fi

  # Reclaim aged temp orphans a SIGKILL/crash left behind (the traps above
  # cover every catch-able exit; this sweep is the mechanism for the rest).
  sweep_stale_tee_temps "$dir"

  # Process-unique temp name with widened entropy; noclobber makes the
  # redirection refuse to follow a pre-planted symlink or overwrite any
  # pre-existing path of the same name. Written in this shell rather than a
  # subshell with its own umask, which would be a process per write: the file
  # takes the inherited umask, and the owner-only directory is what keeps
  # other users out. noclobber is set only for this redirect; the wrapped
  # statusline is a separate process and inherits no shell option.
  local tmp="$dir/.$sid.json.tmp.$$.$RANDOM$RANDOM" wrote=0
  TEE_TMP="$tmp"
  set -o noclobber
  printf '{"captured_at":"%s",%s}\n' "$ts" "$body" 2>/dev/null >"$tmp" && wrote=1
  set +o noclobber
  if ((!wrote)); then
    reclaim_tee_tmp
    return 0
  fi
  # Plausibility ceiling for the no-regression guard below: a target whose
  # captured_at is more than ~5 minutes ahead of this write's own timestamp
  # (clock correction, tampering) must be REPLACED, not honored — honoring
  # it would suppress every refresh until that date and wedge the session
  # in conservative mode. Lexical ISO compare; failure to compute the
  # ceiling disables the guard (write proceeds — fail toward freshness).
  local guard_ceiling=""
  if [[ -n "$now" ]]; then
    TZ=UTC printf -v guard_ceiling '%(%Y-%m-%dT%H:%M:%SZ)T' "$((now + 300))" 2>/dev/null || guard_ceiling=""
  else
    # portability-ok: GNU-first, BSD fallback on the continuation line below (#1510)
    guard_ceiling=$(date -u -d '+5 minutes' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
      date -u -v '+5M' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || guard_ceiling=""
  fi

  local existing_ts line
  for _ in 1 2 3; do
    # Never regress the snapshot: an overlapping same-session refresh may
    # have landed a NEWER captured_at while this process was still building
    # its payload (ISO-8601 UTC compares lexically). Re-checked on every
    # retry. Two residual races are ACCEPTED by design rather than
    # serialized: the check-to-rename microsecond window, and an
    # equal-second tie (captured_at is second-precision, so strict > cannot
    # order two writers born in the same second and the older may win).
    # Worst case for both is a snapshot carrying context data at most one
    # refresh/one second older than the newest — zone bands are coarse and
    # the next refresh supersedes; a lock would add a cross-platform
    # dependency (flock is absent on macOS) for no behavioral difference.
    # The target's captured_at is its first member: both writers here put it
    # first, so a builtin read of the first line finds it; any other shape
    # reads as no timestamp and the write proceeds.
    existing_ts="" line=""
    if [[ -f "$target" ]]; then
      IFS= read -r line 2>/dev/null <"$target" || true
      if [[ "$line" == '{"captured_at":"'* ]]; then
        existing_ts=${line#'{"captured_at":"'}
        existing_ts=${existing_ts%%\"*}
      fi
    fi
    if [[ -n "$existing_ts" && -n "$guard_ceiling" && "$existing_ts" > "$ts" &&
      ! "$existing_ts" > "$guard_ceiling" ]]; then
      reclaim_tee_tmp
      return 0
    fi
    if mv -f "$tmp" "$target" 2>/dev/null; then
      # The temp path is the target now; clear it so the EXIT trap cannot
      # reclaim a name that no longer refers to this refresh's file.
      TEE_TMP=""
      if [[ -n "$now" && ! -L "$last" ]]; then
        printf '%s\n%s\n' "$now" "$body" 2>/dev/null >"$last" || true
      fi
      return 0
    fi
    sleep 0.1 2>/dev/null || true
  done
  reclaim_tee_tmp
  return 0
}

tee_snapshot

if (($#)); then
  # Wrapped mode: transparent passthrough. The wrapped command sees the same
  # stdin bytes and owns stdout; its exit code is the wrapper's. pipefail is
  # dropped for exactly this pipeline: a wrapped command that never reads
  # stdin closes the pipe under printf, and pipefail would surface printf's
  # SIGPIPE (141) instead of the wrapped command's own exit code. printf's
  # stderr is silenced for the same case (bash prints a broken-pipe notice).
  set +o pipefail
  printf '%s' "$INPUT" 2>/dev/null | "$@"
  rc=$?
  set -o pipefail
  if ! command -v jq >/dev/null 2>&1; then
    printf 'context-guard: jq not found — context tee disabled (https://jqlang.org/download/)\n'
  fi
  exit "$rc"
fi

# Standalone mode: minimal statusline when none was configured.
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$INPUT" | jq -r '
    "[\(.model.display_name // "Claude")] ctx \(.context_window.used_percentage // "-")%"
  ' 2>/dev/null || printf 'context-guard: waiting for session data\n'
else
  printf 'context-guard: jq not found — install jq (https://jqlang.org/download/)\n'
fi
exit 0
