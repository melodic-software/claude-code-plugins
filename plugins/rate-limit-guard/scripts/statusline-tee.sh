#!/usr/bin/env bash
# statusline-tee: transparent statusline wrapper that tees the session's
# subscription rate-limit windows to the fixed machine-scope contract path.
#
# SHELL REQUIREMENT: Bash. The statusline `command` runs in a shell; on
# Windows this script requires Git Bash (bash.exe from Git for Windows), so
# the wiring invokes it explicitly as
#   bash "<plugin-root>/scripts/statusline-tee.sh" [wrapped-command...]
# The setup skill (/rate-limit-guard:setup check) prints the exact
# settings.json edit with the resolved path.
#
# Usage:
#   statusline-tee.sh <command> [args...]  Wrap an existing statusline command:
#                                          the stdin JSON passes through to it
#                                          and its stdout and exit code are the
#                                          statusline's, byte-for-byte.
#   statusline-tee.sh                      No statusline configured: act as a
#                                          standalone minimal statusline
#                                          (model, context, both windows).
#
# Tee contract (../reference/reader-contract.md is the authoritative reader
# side): every refresh writes ~/.claude/rate-limit-guard/rate-limits.json —
# one JSON object with captured_at (ISO-8601 UTC) plus, when present on
# stdin, rate_limits and every session-distinguishing top-level field
# (session_id, session_name, and any key whose name contains "account", so a
# future account-identifier field is adopted automatically only when it
# arrives under a top-level key of that shape; every other shape needs a
# writer change).
# The path is deliberately HOME-anchored and outside ${CLAUDE_PLUGIN_DATA}:
# it is a documented cross-plugin artifact seam that sibling-plugin lane
# sessions read, machine-scope by design (the file is last-writer-wins and
# carries no account id today — loop-lane §6 owns that gap's framing).
#
# ATOMICITY: 3+ concurrent sessions write this one path and readers must
# never see torn JSON, so the snapshot is written to a session-unique temp
# file in the same directory and renamed over the target. On Windows,
# renaming over a target another process holds open can fail EACCES (no
# FILE_SHARE_DELETE), so the rename is retried briefly and then SKIPPED —
# the next refresh supersedes a skipped snapshot within seconds, so the skip
# is quiet by design (the durable visibility surface for a persistently
# broken tee is the setup skill's freshness probe). No tee outcome — missing
# jq, unwritable path, failed rename — ever alters the wrapped statusline's
# output or exit code.
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
# ASYNCHRONY (opt-in, RLG_TEE_ASYNC=1, OFF by default -- read the measurements
# before turning it on): the snapshot is a SIDE EFFECT, not an input to the statusline.
# Nothing the wrapped command prints depends on it, and the reader contract
# (../reference/reader-contract.md) budgets ten minutes of staleness, so making
# the render wait for a jq, a lock, a write and a rename buys nothing and costs
# the user a visibly slower status line — roughly 270 ms per refresh on Windows,
# on a path that fires on every assistant message AND every refreshInterval tick,
# once per open session. The snapshot therefore runs in a DETACHED subshell and
# the wrapper returns as soon as the wrapped command does.
#
# This skips no work: every refresh still takes the lock and writes a snapshot,
# just without the render waiting on it. Detachment is threefold and each part is
# load-bearing: stdout and stderr go to /dev/null, or the background child would
# hold the statusline pipe open and Claude Code would keep waiting for EOF long
# after the render finished — cancelling out the entire point; stdin is closed so
# the child can never consume the payload a later reader wants; and the job is
# disowned so the shell does not wait on it at exit.
#
# Two consequences, both already inside the existing contract. A snapshot now
# lands a fraction of a second AFTER the render rather than before it, which the
# staleness budget absorbs. And a cancelled refresh can be killed mid-write, which
# is the case the temp-file-plus-rename, the reclaim traps and the age-filtered
# sweep below were already built for.
#
# WHY IT IS OFF BY DEFAULT. Detaching is a clear win for a single session and a
# clear loss for many, and the crossover is not where intuition puts it. MSYS has
# no native fork(), so forking a bash subshell that has the payload in memory was
# measured at 75-200 ms here, against ~24 ms to exec a small binary. Detaching
# therefore does not make the work cheaper; it buys the render's critical path
# back by paying a fork that is more expensive than the execs it steps around,
# and it lets the work of successive refreshes overlap instead of serialise.
#
# Measured on this repo's harness (Windows, 24 cores), statusline + tee:
#
#   one session, refreshes 1 s apart   sync 660 ms   async 222 ms   (async wins)
#   ten sessions, each at 1 Hz         sync 2265 ms  async 4476 ms  (async loses)
#   ten sessions, peak bash processes  sync 50       async 71       (async loses)
#
# At ten concurrent sessions the fork is paid ten times a second and the detached
# children oversubscribe the box, so the same total work takes twice as long and
# the process count nearly doubles. Sessions, not refresh rate, is the variable
# that decides: turn this on if you run one or two, leave it off if you run many.
# The design that removes the cost rather than moving it -- the render writing
# its payload to a per-session spool file with zero forks, drained by one
# elected render per cadence -- is THE SPOOL below, and is the default from bash
# 4.2 up. This flag is the older answer, kept for the machines where it measured
# well; setting it opts back out of the spool entirely.
#
# Neither default is asynchronous, so "the snapshot has been written" is
# observable the moment the wrapper returns on any refresh that drains, which is
# what the test suite relies on: assertions that a snapshot was NOT written would
# pass vacuously against a race. The suite pins RLG_TEE_DRAIN_INTERVAL=0 so every
# refresh drains, and covers election and the detached path in dedicated cases.
#
# jq is required for the tee and for the standalone line; when absent the
# wrapper stays transparent and appends a visible one-line notice instead of
# silently dropping the feature.

set -uo pipefail

INPUT=""
# Bounded buffered read of the whole stdin payload (Win32 pipes can stall
# before EOF; a truncated payload just fails jq below and tees nothing this
# refresh). read -N buffers in blocks, which matters on Windows/MSYS pipes
# where the -d '' byte-at-a-time loop moves ~40KB/s and can truncate a large
# payload at the timeout (measured on Git Bash); Bash below 4.1 (macOS ships
# 3.2) lacks -N and falls back to the delimiter form, fast enough on native
# POSIX pipes. 1MiB bound: statusline payloads are a few KB.
#
# Deferred into a function rather than run at load: this file carries a sourcing
# guard at the bottom so its enablement gate can be driven by the test suite, and
# a top-level read would consume the sourcing shell's stdin before `main` runs.
read_tee_input() {
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
    IFS= read -r -N 1048576 -t 5 INPUT || true
  else
    IFS= read -r -d '' -t 5 INPUT || true
  fi
  return 0
}

# Path of the temp file currently in flight, for the reclaim traps below. A
# global rather than the function's local: the trap body is evaluated when the
# trap fires, by which time the function's locals are gone.
TEE_TMP=""

reclaim_tee_tmp() {
  [[ -n "$TEE_TMP" ]] && rm -f "$TEE_TMP" 2>/dev/null
  TEE_TMP=""
  return 0
}

# Lock directory currently held (see acquire_tee_lock below); a global for
# the same trap-lifetime reason as TEE_TMP, and defined before the trap is
# installed so an early exit never references an undefined function.
TEE_LOCK=""

release_tee_lock() {
  [[ -n "$TEE_LOCK" ]] && rmdir "$TEE_LOCK" 2>/dev/null
  TEE_LOCK=""
  return 0
}

# Election lock held by an in-process drain (see _rlg_drain below). A SECOND
# lock, deliberately not the snapshot lock: see the DRAIN LOCK note there.
TEE_DRAIN_LOCK=""

release_drain_lock() {
  [[ -n "$TEE_DRAIN_LOCK" ]] && rmdir "$TEE_DRAIN_LOCK" 2>/dev/null
  TEE_DRAIN_LOCK=""
  return 0
}

# The signal traps exit rather than reclaiming directly, so the EXIT trap stays
# the single reclaim path. Exiting is also the right response to a cancelling
# signal: this refresh's snapshot is already superseded by the update that
# cancelled it.
trap 'reclaim_tee_tmp; release_tee_lock; release_drain_lock' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

# Reclaim temp siblings left by a process that never got to clean up. Only
# files older than the age floor are touched, so a concurrent session's live
# temp — sub-second between write and rename — is never a candidate.
#
# The glob runs first and decides whether to spawn at all: on a clean
# directory, which is every refresh in normal operation, this costs zero
# processes on a path that already runs at two to four times the statusline
# debounce interval.
sweep_stale_tee_temps() {
  local dir="$1" candidate
  for candidate in "$dir"/.rate-limits.json.tmp.*; do
    [[ -e "$candidate" ]] || continue
    find "$dir" -maxdepth 1 -type f -name '.rate-limits.json.tmp.*' \
      -mmin +1 -exec rm -f {} + 2>/dev/null || true
    return 0
  done
  return 0
}

# Serialize the preservation decision with the rename. Check-then-write
# without mutual exclusion lets a windowless writer pass its check, lose the
# CPU to a window-bearing writer's rename, and then clobber the fresh windows
# anyway — concurrent sessions are the normal operating model here. The lock
# is a directory (mkdir-as-lock is atomic on every platform this runs on,
# including Git Bash on Windows, where flock is unavailable). A holder killed
# between mkdir and rmdir would leave the lock forever, so a contender steals
# any lock older than the same one-minute age floor the temp sweep uses —
# far above the sub-second hold time of a live writer. The release side lives
# with the traps above.
acquire_tee_lock() {
  local dir="$1" lock="$1/.rate-limits.json.lock" _try
  # shellcheck disable=SC2034  # bounded-retry counter; the value itself is unused
  for _try in 1 2 3; do
    if mkdir "$lock" 2>/dev/null; then
      TEE_LOCK="$lock"
      return 0
    fi
    find "$dir" -maxdepth 1 -type d -name '.rate-limits.json.lock' \
      -mmin +1 -exec rmdir {} + 2>/dev/null || true
    sleep 0.1 2>/dev/null || true
  done
  return 1
}

# Write one contract snapshot. Every failure path returns 0: the tee must
# never propagate into the statusline pipeline.
tee_snapshot() {
  [[ -n "${HOME:-}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0 # visible notice emitted by the caller
  local dir="$HOME/.claude/rate-limit-guard"
  local target="$dir/rate-limits.json"
  # Create-and-harden only when the directory is not already there. Both calls
  # were unconditional and both are processes, so on every refresh after the
  # first they were paying ~50 ms to re-assert a state that already held.
  # Tradeoff, accepted deliberately: the owner-only mode is now asserted at
  # creation instead of re-asserted on every refresh, so a mode a user or tool
  # later loosens on this directory is no longer silently corrected. There is no
  # builtin that can read a mode, so the alternative is a stat process per
  # refresh — the same cost this removes.
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" 2>/dev/null || return 0
    # Owner-only contract dir: keeps other local users from pre-planting
    # symlinks or reading the snapshot. Best-effort (no-op on filesystems
    # without POSIX modes, e.g. Windows ACL volumes under Git Bash).
    chmod 700 "$dir" 2>/dev/null || true
  fi

  # Body and window-bearing verdict both come from _rlg_probe's single jq pass.
  #
  # Window-bearing stays a structural property — jq's has(), never a substring
  # test: a forwarded value that merely contains the string "rate_limits"
  # (e.g. "session_name":"rate_limits") must not count as window-bearing and
  # overwrite a snapshot holding real windows. It is asked of the BUILT payload,
  # exactly as it was when this function ran its own jq.
  local payload="$_RLG_PAYLOAD" has_windows="$_RLG_HAS_WINDOWS"
  [[ -n "$payload" ]] || return 0

  # Sweep before any early return: a machine where only windowless sessions
  # remain active would otherwise skip below on every refresh and never
  # reclaim the orphan a killed window-bearing session left behind.
  sweep_stale_tee_temps "$dir"

  # All writers take the lock around [check+]rename — serialization needs
  # both parties. On acquisition failure the windowless writer skips its
  # write (nothing precious is lost; the reader treats absence reactively),
  # while the window-bearing writer proceeds unlocked: its payload carries
  # data, and last-writer-wins between two window-bearing snapshots is the
  # pre-existing contract.
  if ! acquire_tee_lock "$dir"; then
    [[ "$has_windows" == true ]] || return 0
  fi

  # A session with no windows — API-key or enterprise auth — must not overwrite
  # a snapshot that HAS them. The reader contract routes a snapshot missing
  # rate_limits to whole-guard reactive-only, and this write would carry a FRESH
  # captured_at, so consumers would never see "stale" and would instead see a
  # current snapshot with no data: up to the contract's full 10-minute staleness
  # budget of usable proactive data destroyed on a mixed-auth machine, silently.
  # A target jq cannot parse counts as windowless — torn or corrupt content is
  # exactly what an atomic overwrite should replace.
  if [[ "$has_windows" != true && -f "$target" ]]; then
    if jq -e 'has("rate_limits")' "$target" >/dev/null 2>&1; then
      release_tee_lock
      return 0
    fi
  fi

  local tmp="$dir/.rate-limits.json.tmp.$$.$RANDOM"
  TEE_TMP="$tmp"
  # Subshell umask so the snapshot lands owner-only without altering the
  # umask the wrapped statusline command inherits.
  (
    umask 077
    printf '%s\n' "$payload" >"$tmp"
  ) 2>/dev/null || {
    reclaim_tee_tmp
    release_tee_lock
    return 0
  }
  local _try
  # shellcheck disable=SC2034  # bounded-retry counter; the value itself is unused
  for _try in 1 2 3; do
    if mv -f "$tmp" "$target" 2>/dev/null; then
      # The temp path is the target now; clear it so the EXIT trap cannot
      # reclaim a name that no longer refers to this refresh's file.
      TEE_TMP=""
      release_tee_lock
      return 0
    fi
    sleep 0.1 2>/dev/null || true
  done
  reclaim_tee_tmp
  release_tee_lock
  return 0
}

# The tee's WRITE is plugin behavior and is gated like any other hook's. Two
# things make this call site different from a normal `hook::check_enabled`:
#
#   1. This script is a TRANSPARENT statusline wrapper. `hook::check_enabled`
#      exits 0 on "disabled", which here would suppress the wrapped command's
#      stdout and blank the user's status line. The predicate form skips only
#      the snapshot; the passthrough below stays unconditional.
#   2. This script is invoked BY ABSOLUTE PATH from settings.json `statusLine`,
#      not by the plugin hook runner, so it is reached whatever the plugin's
#      enablement says. Without this gate it is the one code path in the plugin
#      that keeps running when the plugin is off.
#
# If no scope contributes a verdict the tee still runs, consistent with this
# script's rule that no tee outcome ever alters the wrapped statusline.
#
# CHANNEL: this process is NOT a hook process. Claude Code exports
# CLAUDE_PLUGIN_OPTION_<KEY> to hook processes only (plugins-reference, "User
# configuration"; and this repo's docs/conventions/hook-config-delivery/README.md scopes
# the env channel the same way). Reading that variable alone would always find it unset,
# always fall back to enabled, and produce a gate that is decorative -- so the value is
# read from the configured sources directly (channel F), which is the sanctioned route
# for a non-hook consumer. The env var is still honored, but last (see the precedence
# note on _rlg_tee_enabled), in case it is ever delivered here.

# Managed settings — the highest-precedence scope Claude Code honors for
# pluginConfigs (settings docs, "Settings precedence") and the one an organization
# uses to enforce a policy. Fixed, root-owned per-platform paths, the primary file
# first and then the `managed-settings.d/` drop-ins in sorted order; later files
# override earlier ones in _rlg_managed_option, mirroring Claude Code's merge.
#
# Platform comes from `uname -s`, never $OSTYPE — the same spelling as this repo's
# sibling bash channel-F reader, plugins/autonomy/hooks/lane-stop-gate-lib.sh,
# itself the bash equivalent of the python exemplar's sys.platform table
# (plugins/disk-hygiene/lib/killswitch_config.py::managed_settings_path). The
# Windows path is the literal absolute path the docs give, never
# %ProgramFiles%-derived: an environment-derived base would let a repo `env` block
# redirect the highest-precedence scope at the one process that trusts it most.
#
# Server-managed settings are deliberately excluded, as in the sibling reader:
# their only on-disk artifact is the user-writable cache
# ~/.claude/remote-settings.json, which fails this list's trust test.
#
# Prints nothing on an unrecognized platform — managed then configures nothing and
# the user scope decides.
_rlg_managed_settings_files() {
  local primary
  # Fork-free short circuit. `uname` is a process, and this function runs on
  # every statusline refresh only to discover — on the overwhelming majority of
  # machines — that no managed-settings file exists at all. None of the three
  # candidate locations can exist on a platform other than its own, so testing
  # all three with builtins first answers the common case without spawning
  # anything, and the platform table below still decides whenever one of them
  # is actually present.
  local _c _any=""
  for _c in "/Library/Application Support/ClaudeCode/managed-settings" \
    "C:/Program Files/ClaudeCode/managed-settings" \
    "/etc/claude-code/managed-settings"; do
    if [[ -f "$_c.json" || -d "$_c.d" ]]; then
      _any=1
      break
    fi
  done
  [[ -n "$_any" ]] || return 0
  case "$(uname -s 2>/dev/null)" in
  Darwin) primary="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  MINGW* | MSYS* | CYGWIN*) primary="C:/Program Files/ClaudeCode/managed-settings.json" ;;
  Linux) primary="/etc/claude-code/managed-settings.json" ;;
  *) return 0 ;;
  esac
  # Defense in depth: a managed path MUST be absolute (POSIX /… or a Windows
  # drive). A relative value would resolve against this process's cwd — the
  # user's checkout — turning the highest-precedence scope into a plantable file.
  case "$primary" in
  /* | [A-Za-z]:[/\\]*) ;;
  *) return 0 ;;
  esac
  [[ -f "$primary" ]] && printf '%s\n' "$primary"
  local dropin="${primary%/*}/managed-settings.d" f
  if [[ -d "$dropin" ]]; then
    for f in "$dropin"/*.json; do
      [[ -f "$f" ]] && printf '%s\n' "$f"
    done
  fi
  return 0
}

# Print this plugin's configured rate_limit_guard_enabled from ONE settings file
# as "true"/"false"; return 1 when that file contributes no verdict — absent,
# unreadable, unparsable, no matching entry, or a JSON null. Every no-verdict path
# is a fail-OPEN path at the caller.
#
# NOT `// empty` on the value: jq's alternative operator treats `false` as falsy,
# so the one value this gate exists to detect would be discarded. `tostring` yields
# "true"/"false", and emptiness is decided by an explicit `length == 0` on the
# collected array, so no alternative operator ever touches a boolean.
#
# Marketplace-agnostic: pluginConfigs is keyed `<plugin>@<marketplace>`, and this
# plugin may be installed from a fork or private catalog, so the key is matched by
# PREFIX. Last match wins, as in the sibling reader.
#
# The file is opened by bash (`<"$file"`), not by jq: a native jq on Windows
# cannot open an MSYS-style path, while a shell redirection always can. That rules
# out --slurpfile/--rawfile on the settings path as well as on a temp copy of it,
# since $TMPDIR under MSYS is an MSYS path too.
#
# Bash hands the document over in the ENVIRONMENT rather than in jq's argument
# vector. A settings file can hold credentials, and argv is world-readable through
# `ps`/`/proc/<pid>/cmdline` for the life of the process, whereas
# `/proc/<pid>/environ` is owner-only. It also sidesteps the per-argument length
# limit. The prelude below is the only place that reads it, and it parses the
# value INSIDE jq under `try`, so a settings file that will not parse yields an
# empty verdict rather than failing the whole jq invocation — the fail-OPEN
# direction this gate has always taken, and the property a jq-side parse
# (--argjson/--slurpfile) cannot preserve because it dies before the filter runs.
#
# The prelude and the verdict filter are shared verbatim by this function and by
# the single jq pass in _rlg_probe, so the two can never drift into disagreeing
# about what a settings file configures.
# shellcheck disable=SC2016
# $doc is a jq variable and RLG_SETTINGS_DOC is read from jq's own `env`, not by
# the shell: single quotes are required here, and double quotes would have the
# shell substitute empty strings into the filter.
_RLG_DOC_JQ='((env.RLG_SETTINGS_DOC // "null") | (try fromjson catch {})
      | if type == "object" then . else {} end) as $doc'
# shellcheck disable=SC2016
_RLG_VERDICT_JQ='[ ($doc.pluginConfigs // {}) | to_entries[]
      | select(.key | startswith("rate-limit-guard@"))
      | .value.options.rate_limit_guard_enabled
      | select(. != null) | tostring ]
    | if length == 0 then "" else last end'

# The snapshot BODY projection, as a jq function so the live probe and the
# drainer below emit byte-identical bodies from the same text. It is applied to
# a statusline payload object and takes the ISO-8601 timestamp to stamp it with:
# the probe passes its own render time, the drainer passes the OBSERVATION time
# of the record it chose (never "now"), which is what keeps captured_at honest
# about when the windows were seen rather than when they were flushed.
#
# Selection is on the TOP-LEVEL key name only and a selected key carries its
# whole value across — the rule reference/reader-contract.md states.
# shellcheck disable=SC2016  # jq filter text; $ts is a jq parameter, not a shell variable
_RLG_BODY_JQ='def rlg_body($ts): {captured_at: $ts}
      + (to_entries
         | map(select(.key == "rate_limits" or .key == "session_id"
                      or .key == "session_name" or (.key | test("account"; "i"))))
         | from_entries);'

_rlg_settings_option() {
  local file="$1" out
  [[ -r "$file" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  out="$(RLG_SETTINGS_DOC="$(<"$file")" jq -rn "$_RLG_DOC_JQ | $_RLG_VERDICT_JQ" 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# The managed-scope verdict, or return 1 when managed configures none.
_rlg_managed_option() {
  local f v verdict="" have=1
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if v="$(_rlg_settings_option "$f")"; then
      verdict="$v"
      have=0
    fi
  done < <(_rlg_managed_settings_files)
  ((have == 0)) || return 1
  printf '%s' "$verdict"
}

# PRECEDENCE, highest first: managed settings, then user settings, then the
# environment. Absent a verdict from all three the tee runs — the plugin default,
# and the fail-OPEN direction every degraded read lands on.
#
# Managed is authoritative because it is the scope an organization uses to enforce
# a policy and the one no user or project scope can override; a gate that let a
# user (or a repo) out-vote it would be exactly the policy bypass this function is
# supposed to close. The env channel sits BELOW user settings for the same reason
# it is kept at all: it is honored only in case it is ever delivered here, and for
# an UNCONFIGURED key a repo `.claude/settings.json` `env` block freely populates
# CLAUDE_PLUGIN_OPTION_* with no provenance
# (docs/conventions/hook-config-delivery/README.md fact 4), so it must never
# out-vote a value a real settings scope actually configured.
#
# RESIDUALS (accepted; see this plugin's CHANGELOG for the trust analysis): the
# USER settings file is still located from ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
# rather than channel F's install anchor, and a value supplied only through a
# session `--settings` file is invisible to any on-disk read (channel F's own
# documented residual). Neither weakens the MANAGED verdict, which is
# environment-independent by construction.
_rlg_tee_enabled() {
  local v
  if v="$(_rlg_managed_option)"; then
    [[ "$v" == "false" ]] && return 1
    return 0
  fi
  # User scope. _rlg_probe already read this file inside the one jq pass, so the
  # normal path spends no process here. The unprobed fallback keeps a DIRECT
  # call to this function (no main, hence no probe) behaving exactly as it did.
  if ((_RLG_USER_PROBED)); then
    if [[ -n "$_RLG_USER_VERDICT" ]]; then
      [[ "$_RLG_USER_VERDICT" == "false" ]] && return 1
      return 0
    fi
  elif v="$(_rlg_settings_option "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/settings.json")"; then
    [[ "$v" == "false" ]] && return 1
    return 0
  fi
  case "${CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED:-}" in
  "" | true) return 0 ;;
  *) return 1 ;;
  esac
}

# ONE jq pass for everything this script needs to decide and to write: the
# snapshot body, the window-bearing verdict, and the USER-scope enablement
# verdict. Each of those used to be its own jq — three spawns per refresh, at
# ~42 ms each on Windows, on a path that fires on every assistant message AND
# every refreshInterval tick with as many concurrent sessions as the user has
# windows open.
#
# The settings document is read by BASH (`$(<file)`, which bash performs without
# forking) and handed over in the ENVIRONMENT, never opened by jq and never placed
# in its argv: a native jq on Windows cannot open an MSYS-style path (the same
# reason the shell redirection was there before), and argv is world-readable while
# a settings file can hold credentials. See _RLG_DOC_JQ above for the full note.
#
# Everything is wrapped so that no single malformed input can cost more than the
# thing it feeds: a settings file that will not parse yields an empty verdict
# (fail-open, as before) without disturbing the snapshot, and a payload that will
# not parse yields an empty payload without disturbing the gate.
_RLG_PAYLOAD=""
_RLG_HAS_WINDOWS=false
_RLG_USER_VERDICT=""
_RLG_USER_PROBED=0

_rlg_probe() {
  command -v jq >/dev/null 2>&1 || return 0
  local ts settings_file settings_json out line
  # printf's %()T is a bash 4.2+ builtin; macOS statusline Bash 3.2 needs date -u.
  ts=""
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
    TZ=UTC printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || ts=""
  fi
  if [[ -z "$ts" ]]; then
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || return 0
  fi
  [[ -n "$ts" ]] || return 0

  settings_file="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/settings.json"
  settings_json='null'
  if [[ -r "$settings_file" ]]; then
    settings_json="$(<"$settings_file")"
    [[ -n "$settings_json" ]] || settings_json='null'
  fi

  # Settings ride in the environment so credentials never land in jq's argv and no
  # temp file is created; the payload stays on stdin.
  #
  # Three lines out, in a fixed order: payload, window-bearing, user verdict.
  # `jq -c` escapes any newline inside a string and the other two are bare
  # tokens, so every line is single-line by construction and the split is exact.
  out="$(RLG_SETTINGS_DOC="$settings_json" jq -rc --arg ts "$ts" "
    $_RLG_BODY_JQ
    $_RLG_DOC_JQ"'
    | (rlg_body($ts)) as $p
    | $p,
      ($p | has("rate_limits")),
      (try ('"$_RLG_VERDICT_JQ"') catch "")
  ' <<<"$INPUT" 2>/dev/null)" || return 0

  local -a lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines[${#lines[@]}]="$line"
  done <<<"$out"
  _RLG_PAYLOAD="${lines[0]:-}"
  [[ "${lines[1]:-}" == true ]] && _RLG_HAS_WINDOWS=true
  # An unparsable payload means jq produced nothing usable; leave the user
  # verdict unprobed so the gate falls back to its own read rather than
  # silently reading "no verdict configured" off a failed parse.
  if [[ -n "$_RLG_PAYLOAD" ]]; then
    _RLG_USER_VERDICT="${lines[2]:-}"
    _RLG_USER_PROBED=1
  fi
  return 0
}

# Probe, gate and snapshot as one unit. The gate lives in here with the write it
# governs rather than in the caller: it decides nothing the foreground needs, and
# its managed-scope lookup can itself cost a process, so keeping the pair together
# is what lets the foreground spend exactly one fork on the whole feature.
_rlg_tee_run() {
  _rlg_probe
  if _rlg_tee_enabled; then
    tee_snapshot
  fi
  return 0
}

# =============================== THE SPOOL ==================================
#
# The render path above costs a jq, a lock, a write and a rename on EVERY
# refresh — once per assistant message and once per refreshInterval tick, per
# open session. Measured same-window here (Windows/MSYS, n=9): render.sh alone
# 234.4 ms, render.sh + this wrapper 1047.1 ms. The wrapper dominates, and the
# dominant term in the wrapper is process creation, which MSYS has no cheap
# primitive for. So the render stops doing the work: it APPENDS NOTHING and
# FORKS NOTHING, it overwrites one small per-session file with builtins, and
# one elected render per cadence flushes the batch into the same contract
# snapshot the same tee_snapshot writes today.
#
# WHY PER-SESSION FILES, NOT ONE SHARED APPEND SPOOL. A shared O_APPEND spool
# would be the obvious shape and it is not safe here. POSIX guarantees
# atomicity for concurrent writes to PIPES up to PIPE_BUF; for REGULAR FILES it
# explicitly leaves concurrent-write behaviour unspecified. Through
# Cygwin/MSYS the observed no-interleave bound on appends is around a kilobyte
# while statusline payloads are multiple kilobytes, and bash's buffered builtin
# output can split one large record across syscalls regardless. Atomicity is
# therefore obtained from FILE DISJOINTNESS instead of from any write-size
# argument: no two writers ever share a file, each record is one line written
# with a TRUNCATING '>', and a reader either sees the previous complete record
# or the new one. A record that is torn anyway (killed mid-write) fails
# `fromjson` in the drain and is dropped.
#
# THE FILENAME IS A SHARD KEY, NEVER TRUSTED DATA. session_id is extracted from
# the payload with parameter expansion and must match ^[A-Za-z0-9._-]{1,64}$
# and not begin with a dot; anything else — a traversal attempt, an embedded
# quote, a 200-character value, a JSON null — shards to the literal name
# `misc`. Sessions that collide on `misc` overwrite each other's record, which
# costs one refresh of freshness and nothing else.
#
# DRAIN LOCK. The election takes its OWN lock (spool/.drain.lock), not the
# snapshot lock. Two reasons, both load-bearing: tee_snapshot acquires and
# releases the snapshot lock through one global, so a drain holding it would
# have tee_snapshot burn its full retry budget and then rmdir the lock out from
# under its own caller; and the snapshot lock's existing semantics — a
# window-bearing writer proceeds through a lock it could not take — must keep
# working, which a drain gated on that same lock would break.
#
# TRIGGER. There is no timer to hang this on: Claude Code hooks are strictly
# event-driven (https://code.claude.com/docs/en/hooks.md) and none fires on a
# schedule, an OS scheduler would mean three mechanisms across three platforms,
# and a resident lock-holder would have to be forked off a render — the one
# thing this design exists to stop — and would be killed with it, since Claude
# Code cancels in-flight statusline scripts. The renders themselves are the
# clock: whichever one finds the stamp older than the cadence does the work,
# in-process, for everyone.
#
# BASH FLOOR. %(%s)T is a bash 4.2 builtin. Below that (macOS ships 3.2) the
# synchronous path above runs untouched — and that is the platform where fork
# is cheap and this problem does not exist. RLG_TEE_ASYNC=1 also keeps its
# current behaviour.

# Extract session_id from the raw payload with parameter expansion only, and
# reduce it to a safe shard name. Sets _RLG_SHARD.
_RLG_SHARD=""
_rlg_shard_name() {
  local rest="${INPUT#*\"session_id\"}" sid=""
  if [[ "$rest" != "$INPUT" ]]; then
    rest="${rest#*\"}"
    sid="${rest%%\"*}"
  fi
  # Charset AND a leading-dot rejection: a name beginning with a dot would be
  # skipped by the drain's spool glob, letting a session's own record sit
  # unread forever.
  if [[ "$sid" =~ ^[A-Za-z0-9._-]{1,64}$ && "$sid" != .* ]]; then
    _RLG_SHARD="$sid"
  else
    _RLG_SHARD="misc"
  fi
  return 0
}

# Take the election lock, or return 1. No retry loop and no sleep: a render
# that loses the election has nothing to wait for — the winner is doing the
# work — so the collapse costs exactly one failed mkdir. The stale-lock steal
# is attempted only when the stamp itself is far past due, which is the only
# state a lock abandoned by a killed holder can produce.
acquire_drain_lock() {
  local spool="$1" steal="$2" lock="$1/.drain.lock"
  if mkdir "$lock" 2>/dev/null; then
    TEE_DRAIN_LOCK="$lock"
    return 0
  fi
  ((steal)) || return 1
  find "$spool" -maxdepth 1 -type d -name '.drain.lock' \
    -mmin +2 -exec rmdir {} + 2>/dev/null || true
  if mkdir "$lock" 2>/dev/null; then
    TEE_DRAIN_LOCK="$lock"
    return 0
  fi
  return 1
}

# Flush the spool into one contract snapshot. Runs IN-PROCESS in the elected
# render: detaching would pay back the fork this whole design removes.
_rlg_drain() {
  local dir="$1" spool="$2" now="$3" self="$4" interval="$5" steal="$6"
  local marker="$dir/.tee-disabled" stamp="$spool/.last-drain"
  command -v jq >/dev/null 2>&1 || return 0
  acquire_drain_lock "$spool" "$steal" || return 0

  # Re-read the stamp UNDER the lock. Without this, every render that queued
  # behind the winner would drain again the moment the winner released.
  local last2=0
  if [[ -f "$stamp" ]]; then
    IFS= read -r last2 <"$stamp" || last2=0
  fi
  [[ "$last2" =~ ^[0-9]+$ ]] || last2=0
  if ((now - last2 < interval)); then
    release_drain_lock
    return 0
  fi

  # Records from sessions that are gone. The floor is 15 minutes — far past the
  # reader contract's 10-minute staleness budget, so nothing still usable is
  # ever swept, and far past any live session's refresh interval.
  find "$spool" -maxdepth 1 -type f -name '*.json' \
    -mmin +15 -exec rm -f {} + 2>/dev/null || true

  local batch="" f line
  for f in "$spool"/*.json; do
    [[ -f "$f" ]] || continue
    IFS= read -r line <"$f" || true
    [[ -n "$line" ]] || continue
    batch+="$line"$'\n'
  done

  local settings_file settings_json out
  settings_file="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/settings.json"
  settings_json='null'
  if [[ -r "$settings_file" ]]; then
    settings_json="$(<"$settings_file")"
    [[ -n "$settings_json" ]] || settings_json='null'
  fi

  # ONE jq pass, same three lines in the same order _rlg_probe emits, so
  # everything downstream is shared code. Lines are read raw and parsed under
  # `try` so a torn record is dropped instead of failing the batch. The chosen
  # record is the newest WINDOW-BEARING one, falling back to the newest overall
  # when the machine has no window-bearing session at all; ties on the
  # one-second stamp are broken in favour of THIS render's own shard, whose
  # observation is the freshest by construction.
  if [[ -n "$batch" ]]; then
    out="$(RLG_SETTINGS_DOC="$settings_json" jq -Rrcn --arg self "$self" "
      $_RLG_BODY_JQ
      $_RLG_DOC_JQ"'
      | [ inputs
          | (try fromjson catch empty)
          | select(type == "object" and (.e | type) == "number"
                   and (.p | type) == "object") ] as $recs
      | ([ $recs[] | select(.p | has("rate_limits")) ]) as $win
      | (if ($win | length) > 0 then $win else $recs end) as $pool
      | if ($pool | length) == 0 then empty
        else
          ($pool | map(.e) | max) as $maxe
          | ([ $pool[] | select(.e == $maxe) ]) as $tied
          | (([ $tied[] | select(.p.session_id == $self) ] | last)
             // ($tied | last)) as $chosen
          | ($chosen.p | rlg_body($chosen.e | floor | todate)) as $body
          | $body,
            ($body | has("rate_limits")),
            (try ('"$_RLG_VERDICT_JQ"') catch "")
        end
    ' <<<"$batch" 2>/dev/null)" || out=""
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      lines[${#lines[@]}]="$line"
    done <<<"$out"
    _RLG_PAYLOAD="${lines[0]:-}"
    [[ "${lines[1]:-}" == true ]] && _RLG_HAS_WINDOWS=true
    if [[ -n "$_RLG_PAYLOAD" ]]; then
      _RLG_USER_VERDICT="${lines[2]:-}"
      _RLG_USER_PROBED=1
    fi
  fi

  # Bootstrap, or every line torn: fall back to this render's own payload so the
  # first-ever refresh on a machine still snapshots immediately.
  [[ -n "$_RLG_PAYLOAD" ]] || _rlg_probe

  if _rlg_tee_enabled; then
    [[ -e "$marker" ]] && rm -f "$marker" 2>/dev/null
    tee_snapshot
  else
    # Stamp the marker so the render path can stop spooling with one builtin
    # test, and drop what is already spooled — a disabled plugin holds no data.
    printf '%s\n' "$now" >"$marker" 2>/dev/null || true
    local any=""
    for f in "$spool"/*.json; do
      [[ -f "$f" ]] || continue
      any=1
      break
    done
    [[ -n "$any" ]] && rm -f "$spool"/*.json 2>/dev/null
  fi

  printf '%s\n' "$now" >"$stamp" 2>/dev/null || true
  release_drain_lock
  return 0
}

# The zero-fork render path. Every construct below is a bash builtin: no `$( )`
# anywhere, because command substitution forks a subshell and the subshell fork
# is the cost being removed.
_rlg_spool_dispatch() {
  [[ -n "${HOME:-}" ]] || return 0
  [[ -n "$INPUT" ]] || return 0
  local dir="$HOME/.claude/rate-limit-guard" spool="$HOME/.claude/rate-limit-guard/spool"

  # Cold start only, exactly as tee_snapshot guards its own directory. The
  # owner-only mode is asserted on the PARENT at creation; spool/ inherits its
  # protection from that, since traversal is what gates access to a child.
  if [[ ! -d "$spool" ]]; then
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir" 2>/dev/null || return 0
      chmod 700 "$dir" 2>/dev/null || true
    fi
    mkdir "$spool" 2>/dev/null || return 0
  fi

  local now
  printf -v now '%(%s)T' -1 2>/dev/null || return 0

  # Disabled: a drain wrote this marker after reading the real gate. Rechecking
  # costs a jq, so it happens on a cadence rather than per refresh; until then
  # this render does nothing at all.
  local marker="$dir/.tee-disabled" m=0
  if [[ -f "$marker" ]]; then
    IFS= read -r m <"$marker" || m=0
    [[ "$m" =~ ^[0-9]+$ ]] || m=0
    ((now - m < ${RLG_TEE_DISABLED_RECHECK:-300})) && return 0
  fi

  # JSON strings cannot contain a raw CR or LF, so stripping them cannot change
  # what a parser reads — and it guarantees the record is exactly one line.
  local payload="${INPUT//$'\r'/}"
  payload="${payload//$'\n'/}"

  _rlg_shard_name
  printf '{"e":%s,"p":%s}\n' "$now" "$payload" >"$spool/$_RLG_SHARD.json" 2>/dev/null || return 0

  local interval="${RLG_TEE_DRAIN_INTERVAL:-30}" stamp="$spool/.last-drain" last=0
  [[ "$interval" =~ ^[0-9]+$ ]] || interval=30
  if [[ -f "$stamp" ]]; then
    IFS= read -r last <"$stamp" || last=0
  fi
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  ((now - last >= interval)) || return 0

  local steal=0
  ((now - last >= interval + 120)) && steal=1
  _rlg_drain "$dir" "$spool" "$now" "$_RLG_SHARD" "$interval" "$steal"
  return 0
}

rlg_tee_dispatch() {
  if [[ "${RLG_TEE_ASYNC:-0}" != "1" ]]; then
    if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
      _rlg_spool_dispatch
    else
      _rlg_tee_run
    fi
    return 0
  fi
  # See ASYNCHRONY at the top of this file for why all three redirections are
  # required rather than merely tidy.
  _rlg_tee_run >/dev/null 2>&1 </dev/null &
  # Job control is off in this shell, so `disown` may legitimately have nothing
  # to do; the shell does not wait on background jobs at exit either way.
  disown "$!" 2>/dev/null || true
  return 0
}

main() {
  read_tee_input
  rlg_tee_dispatch

  if (($#)); then
    # Wrapped mode: transparent passthrough. The wrapped command sees the same
    # stdin bytes and owns stdout; its exit code is the wrapper's. pipefail is
    # dropped for exactly this pipeline: a wrapped command that never reads
    # stdin closes the pipe under printf, and pipefail would surface printf's
    # SIGPIPE (141) instead of the wrapped command's own exit code. printf's
    # stderr is silenced for the same case (bash prints a broken-pipe notice).
    local rc
    set +o pipefail
    printf '%s' "$INPUT" 2>/dev/null | "$@"
    rc=$?
    set -o pipefail
    if ! command -v jq >/dev/null 2>&1; then
      printf 'rate-limit-guard: jq not found — rate-limit tee disabled (https://jqlang.org/download/)\n'
    fi
    exit "$rc"
  fi

  # Standalone mode: minimal statusline when none was configured.
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r '
      def pct(w): ((w // {}) | if .used_percentage != null then "\(.used_percentage)%" else "-" end);
      "[\(.model.display_name // "Claude")] ctx \(.context_window.used_percentage // "-")% | 5h "
      + pct(.rate_limits.five_hour) + " | 7d " + pct(.rate_limits.seven_day)
    ' 2>/dev/null || printf 'rate-limit-guard: waiting for session data\n'
  else
    printf 'rate-limit-guard: jq not found — install jq (https://jqlang.org/download/)\n'
  fi
  exit 0
}

# Sourcing guard (the idiom already used by this repo's updater scripts): `main`
# runs only on a direct invocation, so a direct run is byte-for-byte what it was,
# while the test suite can SOURCE this file to stub _rlg_managed_settings_files —
# whose paths are fixed and root-owned by design, therefore unwritable from a
# test — and then drive the real end-to-end path through `main`.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
