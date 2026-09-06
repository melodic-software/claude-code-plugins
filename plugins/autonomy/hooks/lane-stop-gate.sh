#!/usr/bin/env bash
# Stop hook: the deterministic lane-stop gate (autonomy #535 member 3) plus the
# operator STOP-notification (member 4).
#
# "A lane that stops itself before its goal is met is a bug" is otherwise only a
# prompt admonition. This hook fires on every stop attempt of an opted-in
# autonomous lane and structurally intercepts it: unless completion is EXPLICITLY
# signaled, the first stop attempt is blocked with a re-injected completion
# self-check (converting a silent premature stop into "keep going or declare
# done"), and a lane that still stops after that one nudge is treated as a
# genuine down-lane — allowed to stop (never wedged) and the operator is alerted.
#
# SCOPE — this gate mechanizes ONE clause of the autonomous-pipeline reminder
# (reference/autonomous-pipeline-reminder.md): end the turn only on completion or
# a genuine block. It performs no content classification of the final message
# beyond the literal sentinel check below, so it cannot tell a blocked-on-user
# stop from a lazy one — both get the same single nudge. Every other clause of
# that reminder is carried by instruction alone; a shell hook cannot judge
# whether a final paragraph describes an action or reports one.
#
# DEFAULT-OFF. A Stop-blocking hook that engaged by default would wedge every
# interactive user's stop, so the gate is inert unless a session explicitly opts
# in. Every other exit path allows the stop.
#
# FAIL-OPEN. Unlike a PreToolUse guard (which fails closed to deny), a Stop gate
# that fails closed would trap a lane it cannot evaluate. On unreadable stdin,
# missing jq, or a non-Stop event it allows the stop. An unreadable or malformed
# TRUSTED CONFIG source likewise contributes no verdict — the default (off)
# applies — but an enablement claimed only on the untrusted env channel gets a
# visible once-per-session notice rather than a silent disengage.
#
# CONFIG IS READ FROM TRUSTED SOURCES ONLY (#1784). The gate never reads
# `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_*` straight off the environment as a
# value: that is channel B of docs/conventions/hook-config-delivery, whose
# unset case a watched repository's own `.claude/settings.json` `env` block
# owns, and a gate whose enablement (or sentinel, or marker path) the watched
# repository controls is not a gate. Per-key resolution is, in precedence
# order:
#
#   1. managed settings (fixed root-owned paths + managed-settings.d drop-ins);
#   2. the per-session ARM RECORD: the claude-ops lane launcher arms a lane at
#      launch via this plugin's hooks/lane-stop-gate-arm.sh, which writes a
#      record under the plugin's own install-derived data directory; the session
#      carries only a random record id through the `lane_stop_gate_arm_id`
#      userConfig option. The env-delivered id is a capability POINTER, never
#      authority: it is shape-validated, looked up only in the install-derived
#      store, claimed by the first session that presents it through an exclusive
#      create so concurrent presenters cannot both win (a different session
#      replaying the same id is refused), and TTL-bounded — it lives for the
#      claiming session's whole life (every /loop cycle's stop stays gated),
#      retired by TTL and the launcher's relaunch sweep, never by a single stop;
#   3. user settings.json, located only from this script's own install path;
#   4. the in-script defaults (enabled=false, sentinel=LANE-STOP-OK, no marker).
#
# The `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED/SENTINEL/MARKER` env mirrors
# are never read as values. ENABLED/ARM_ID presence is used ONLY to decide
# whether to evaluate at all and to surface the visible not-honored notice.
#
# Completion signal (either is sufficient, checked deterministically — a shell
# hook cannot re-run the /goal evaluator model):
#   - the exact sentinel token (default LANE-STOP-OK) in the agent's final
#     message, matched only when it stands alone on its own line, or
#   - the existence of the configured marker file (consumed on use, so a prior
#     run's leftover marker never authorizes a later run). Consumption is
#     recorded in this plugin's own data directory, not carried solely by the
#     file's deletion: an `rm` the hook is not permitted to perform must not
#     leave a file a later run reads as a live signal.
#
# Config (userConfig keys, delivered per the precedence above):
#   lane_stop_gate_enabled     opt a session in (default false)
#   lane_stop_gate_sentinel    completion token (default LANE-STOP-OK)
#   lane_stop_gate_marker      completion-marker file (absolute, or relative to
#                              the session cwd; default unset)
#   lane_stop_gate_arm_id      launcher-written arm-record id (never authority)

set -uo pipefail
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=lane-notify.sh
source "$HOOK_DIR/lane-notify.sh"
# shellcheck source=lane-stop-gate-lib.sh
source "$HOOK_DIR/lane-stop-gate-lib.sh"
case "$HOOK_DIR" in
/* | ?:[/\\]*) gate_resolve_install "$HOOK_DIR/.." || true ;;
*) gate_resolve_install "$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)" || true ;;
esac

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on an older host it is empty and hook::emit_telemetry skips fail-open.
START=${EPOCHREALTIME:-}

# emit_tel <status> <outcome> <signal> — fire-and-forget telemetry for an
# EVALUATED gate outcome (hook-telemetry convention; no-op unless the consumer
# sets HOOK_TELEMETRY_SINK). Only the three evaluated outcomes emit; the
# fail-open/skip exits stay silent — they are pre-evaluation, and emitting on
# every interactive default-off stop would be noise, not signal. The payload is
# a closed fixed vocabulary by design: never the sentinel value, the marker
# path, the cwd, or the branch, so the envelope cannot leak the completion
# token or lane-identifying paths into the sink.
#
# The data object is assembled in the shell, not by `jq -nc --arg …`: both
# fields are literals from the closed vocabulary at the call sites below (no
# quote, backslash or control byte among them), so the bytes are the ones jq's
# compact printer wrote — `{"outcome":"…","signal":"…"}` — without spending a
# process on every evaluated stop, sink or no sink.
emit_tel() {
  local data='{"outcome":"'"$2"'","signal":"'"$3"'"}'
  hook::emit_telemetry "lane-stop-gate" "Stop" "$1" "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# jq-free AND stdin-free pre-filter: is the gate plausibly configured anywhere
# this host could honor — or at least CLAIMED, which must produce the visible
# notice below rather than silence? Sessions with no gate footprint at all (the
# interactive default) exit here, before the stdin buffer and the jq gate, so an
# unarmed session never pays the buffered read for a decision it cannot make,
# and a jq-less machine never sees a lane-stop-gate notice for a session that
# never opted in. The env presence tests grant no authority: a hit only routes
# into evaluation, where the trusted sources decide.
#
# Everything this reads is already in scope above: the two env presences, and
# the two settings-file locators from lane-stop-gate-lib.sh — gate_user_settings_file_to,
# which derives from the GATE_CONFIG_ROOT that gate_resolve_install establishes
# at the top of this file, and gate_managed_settings_files_load, which depends
# on nothing but `uname -s` and fixed absolute paths.
# Nothing here is payload-derived, so it MUST stay above the buffer — and
# everything payload-derived (hook::require_jq, EVENT, SESSION_ID, and the
# SubagentStop-versus-Stop discrimination) MUST stay below it (#2852).
#
# This is the path every interactive stop takes, so it spawns nothing but the
# `uname -s` inside the managed-files load: the file scan is a builtin read
# where it used to be a `grep -q` process, and the locators write into
# variables where they used to be captured through a subshell. The loaded
# managed list is kept for the option resolution below, which would otherwise
# ask uname again.
gate_maybe_configured() {
  [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" ]] && return 0
  [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED:-}" ]] && return 0
  local f
  if gate_user_settings_file_to f && [[ -f "$f" ]]; then
    gate_file_mentions "$f" && return 0
  fi
  gate_managed_settings_files_load
  for f in ${GATE_MANAGED_FILES[@]+"${GATE_MANAGED_FILES[@]}"}; do
    [[ -n "$f" ]] || continue
    gate_file_mentions "$f" && return 0
  done
  return 1
}
# gate_file_mentions <file> — `grep -q lane_stop_gate <file>` with no process:
# the file is read in NUL-delimited chunks (a `read -d ''` returns 1 at EOF
# while still assigning the final chunk) and each chunk is substring-tested.
# The token holds no NUL, so it cannot straddle a chunk boundary, and an
# unreadable file yields no chunk, which is the same "no match" grep gave.
#
# `2>/dev/null` is written BEFORE the input redirection, and the order is
# load-bearing: bash applies a command's redirections left to right, so with
# the input first an open that fails — an existing settings file this hook may
# not read — reports "Permission denied" on the stderr the next redirection was
# about to silence. The old `grep … 2>/dev/null` was silent there, and this hook
# runs on every Stop, so the noise would be per-turn. Silencing stderr first
# keeps it silent; the verdict (no chunk, return 1) is the same either way.
gate_file_mentions() {
  local chunk=""
  # Terminates: every successful read consumed a NUL, and at EOF `read`
  # assigns the empty remainder and returns 1, which ends the loop.
  while IFS= read -r -d '' chunk || [[ -n "$chunk" ]]; do
    [[ "$chunk" == *lane_stop_gate* ]] && return 0
  done 2>/dev/null <"$1"
  return 1
}
gate_maybe_configured || exit 0

# Buffer stdin. Empty (rc 1) or timed-out (rc 2) → allow the stop (fail-open: a
# gate that cannot read the payload must not trap the lane).
INPUT=$(hook::buffer_stdin) || exit 0

# jq parses the payload and the trusted config. Absent → visible once-per-session
# notice, then allow the stop (fail-open). Stop supports additionalContext, so
# the notice reaches both the agent and the user.
hook::require_jq "Stop" "autonomy-lane-stop-gate" "$INPUT"

# Every payload field the gate reads, in ONE jq pass (hook::jq_fields, the
# shared helper): five `printf | jq | tr` pipelines used to read the same
# buffer one field at a time, each a subshell plus two pipeline forks plus the
# `tr`. The helper's values are CR-stripped, as the `tr -d '\r'` here was, and a
# malformed payload leaves every field empty, which exits at the event guard
# exactly as an empty per-field read did. `// false | tostring` keeps
# stop_hook_active reading "false" (not the helper's empty default) when the
# key is absent, the value `jq -r '… // false'` printed.
#
# The five values are then chomped the way the `$( )` captures chomped them —
# trailing newlines only — so each reads byte-for-byte as before.
chomp_nl() {
  local __v="${!1}"
  while [[ "$__v" == *$'\n' ]]; do __v="${__v%$'\n'}"; done
  printf -v "$1" '%s' "$__v"
}
hook::jq_fields "$INPUT" \
  '.hook_event_name // ""' \
  '.session_id // ""' \
  '.cwd // ""' \
  '.stop_hook_active // false | tostring' \
  '.last_assistant_message // ""' || HOOK_JQ_FIELDS=()
EVENT="${HOOK_JQ_FIELDS[0]-}"
SESSION_ID="${HOOK_JQ_FIELDS[1]-}"
CWD="${HOOK_JQ_FIELDS[2]-}"
STOP_ACTIVE="${HOOK_JQ_FIELDS[3]-}"
LAST="${HOOK_JQ_FIELDS[4]-}"
chomp_nl EVENT
chomp_nl SESSION_ID
chomp_nl CWD
chomp_nl STOP_ACTIVE
chomp_nl LAST

# Fire ONLY on a true top-level session stop. A subagent finishing is delivered
# as SubagentStop; guarding on the event name keeps a Task-tool worker's normal
# completion from ever tripping the lane gate, whichever way the platform routes
# the registration.
[[ "$EVENT" == "Stop" ]] || exit 0

# --- Arm record ---------------------------------------------------------------
# Load (and claim) the arm record named by the env-carried id, if any. Success
# sets GATE_ARM_JSON and means: this session was armed by the operator-side
# launcher. TTL keeps a crashed lane's record from outliving its usefulness; the
# session claim makes a replayed id (e.g. one a lane leaked and a repo env block
# later serves to a different session) worthless.
GATE_ARM_TTL_SECONDS=$((7 * 86400))
GATE_ARM_JSON=""

# Does this session own the record whose claim sidecar is <claim path>?
#
# The claim is an EXCLUSIVE CREATE — `set -o noclobber` on a `>` redirection,
# i.e. open with O_CREAT|O_EXCL — the same primitive statusline-tee.sh uses for
# its snapshot write, extended from a process-unique name to mutual exclusion on
# a contended one. Read-then-write of the record itself cannot decide this:
# two Stop invocations presenting the same fresh id both read it unclaimed, both
# write, and the last rename wins, so BOTH honor the arm for that event while
# the loser — possibly the legitimate lane — is refused on every later stop.
# flock is not used: it is absent on macOS, the reason statusline-tee.sh already
# records for avoiding it.
#
# FAIL DIRECTION: a store this hook cannot write leaves no claim file
# at all and the arm is HONORED. Being gated is never the harm here; the harm is
# a legitimate lane silently losing its gate. The existence recheck that tells
# "another session claimed it" apart from "an unwritable store" shares that
# direction, and so does the fall-through below: durably ownerless — a create
# that won whose write never landed — or a durably unwritable store honors every
# presenter for as long as it lasts, the same unbounded over-gating a failed
# claim write produces, in the same direction. An extra nudge, never an
# ungated lane.
#
# The claim file exists ONLY because some process won the exclusive create, so
# an EMPTY one is that winner caught between its create and its write, not an
# ownerless record. Honoring it there would hand one fresh arm to every
# concurrent presenter — the race this claim exists to close, reopened a few
# microseconds wide — so the read is retried over a bounded budget to let the
# winner's line land. Bounded, and the fall-through is still HONOR: refusing a
# durably ownerless claim would make the record permanently unclaimable, which
# is the original harm in a new shape.
#
# The comparison runs on a newline-stripped session id so the value written and
# the value read back are the same shape whatever the payload carried.
gate_arm_owned() {
  local claim="$1" me="${SESSION_ID//[$'\r\n']/}" owner=""
  # The record path has always been guarded by `[[ -f ]]`; the claim is a second
  # predictable name in the same store and earns the same asymmetry. Anything
  # sitting there that this hook did not write is not a claim: a FIFO would
  # block the write with no reader and hang the whole Stop event, a directory or
  # a symlink aimed elsewhere decides nothing. Leave it untouched and honor.
  [[ ! -e "$claim" || (-f "$claim" && ! -L "$claim") ]] || return 0
  if [[ -n "$me" ]] && (
    # umask 077 is best-effort on MSYS (the claim may still land 644); the
    # exclusive-create is what binds the record, not the file mode.
    umask 077
    set -o noclobber
    printf '%s\n' "$me" >"$claim"
  ) 2>/dev/null; then
    return 0
  fi
  [[ -e "$claim" ]] || return 0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    # `|| true`, never `|| owner=""`: read reports failure on a final line with
    # no newline yet still assigns it, and clearing that would discard a real
    # owner.
    IFS= read -r owner <"$claim" 2>/dev/null || true
    [[ -n "$owner" ]] && break
    # A userland whose sleep rejects a fraction leaves a tight re-read, which is
    # a narrower budget but never a wrong answer.
    sleep 0.02 2>/dev/null || true
  done
  [[ -n "$owner" ]] || return 0
  [[ -n "$me" && "$owner" == "$me" ]]
}

# The record is read in ONE jq pass that yields, NUL-separated: armed_at,
# session_id, the sentinel and marker options (each `v:<value>`, or `-` when
# the record carries no string for it) and the compact document. Three jq
# processes used to read it — a validating `jq -ec .`, then one `printf | jq`
# pipeline per field — and two more ran later, one per option the arm record
# was asked for. The verdicts are unchanged: a document jq cannot parse, or
# one that is not an object, yields no records and is refused exactly as the
# failed validation refused it; `null` yields an empty armed_at and is refused
# at the digit check, as `-e` refused it. The separator is `[0] | implode` so
# the program text carries no NUL byte, and the value read for each field is
# chomped of trailing newlines as the former `$( )` captures were.
GATE_ARM_OPT_HAVE=(0 0 0)
GATE_ARM_OPT_VALUE=("" "" "")
gate_load_arm_record() {
  local id="${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" rec claim armed_at now claimed f
  local -a fields=()
  [[ -n "$id" ]] || return 1
  gate_arm_record_path_to rec "$id" || return 1
  gate_arm_claim_path_to claim "$id" || return 1
  [[ -f "$rec" ]] || return 1
  {
    while IFS= read -r -d '' f; do
      while [[ "$f" == *$'\n' ]]; do f="${f%$'\n'}"; done
      fields+=("$f")
    done < <(jq -j '
      [ (.armed_at // "" | tostring),
        (.session_id // "" | tostring),
        (.sentinel | if type == "string" then "v:" + . else "-" end),
        (.marker | if type == "string" then "v:" + . else "-" end),
        tojson ] | .[] | (., ([0] | implode))')
  } <"$rec" 2>/dev/null
  ((${#fields[@]} == 5)) || return 1
  armed_at="${fields[0]}"
  [[ "$armed_at" =~ ^[0-9]+$ ]] || return 1
  # EPOCHSECONDS (Bash 5.0+) is the same wall clock `date +%s` reads, without
  # the process; an older bash still pays the date.
  now="${EPOCHSECONDS:-}"
  [[ "$now" =~ ^[0-9]+$ ]] || { { now=$(date +%s); } 2>/dev/null || now=""; }
  if [[ -n "$now" ]] && ((now - armed_at > GATE_ARM_TTL_SECONDS)); then
    rm -f -- "$rec" "$claim" 2>/dev/null
    return 1
  fi
  # Compatibility read: a record claimed before the sidecar existed carries its
  # owner in the record itself and has no claim file. That field stays
  # authoritative so an upgrade cannot let a second session claim a record
  # already bound to a live lane; nothing writes it any more. Mid-lane downgrade
  # (newer hook → older without sidecar support) can leave a sidecar the older
  # hook ignores — over-gating only; re-arm after downgrade.
  claimed="${fields[1]}"
  if [[ -n "$claimed" ]]; then
    [[ -n "$SESSION_ID" && "$claimed" == "$SESSION_ID" ]] || return 1
  else
    gate_arm_owned "$claim" || return 1
  fi
  # Assigned only past the ownership verdict: an unowned record contributes no
  # config, which is what keeps a replaying session from being honored at all.
  # The option slots are index-parallel to GATE_OPTION_KEYS below (enabled is
  # implied by the arm itself and never read from the record).
  if [[ "${fields[2]}" == v:* ]]; then
    GATE_ARM_OPT_HAVE[1]=1
    GATE_ARM_OPT_VALUE[1]="${fields[2]#v:}"
  fi
  if [[ "${fields[3]}" == v:* ]]; then
    GATE_ARM_OPT_HAVE[2]=1
    GATE_ARM_OPT_VALUE[2]="${fields[3]#v:}"
  fi
  GATE_ARM_JSON="${fields[4]}"
}
gate_load_arm_record || true

# The arm record is NOT consumed on a stop. A lane is one session across many
# /loop cycles (claude-ops lanes/context/refresh.md), and each cycle ends in a
# Stop the gate must still guard; deleting the record on the first
# completion-signaled or post-nudge stop would silently disarm every later
# cycle. The record instead lives for the claiming session — bound to it by the
# session-id claim above, so no other session can use it — and is retired by its
# TTL (checked on load) plus the launcher's own `find -mtime` sweep at the next
# relaunch.

# Per-key resolution: managed ▷ arm record ▷ user settings ▷ caller default
# (return 1). An armed session IS enabled; its record may also carry the
# sentinel and marker the launcher captured from the lane's config.
#
# gate_option_to <var> <key> writes the value into <var> in this shell. Each
# scope is read ONCE for all three keys, on first need, and answered from
# memory after that: the managed files and the user settings file each cost
# one jq per file (gate_settings_options_to) instead of one per file per key,
# and the arm record was read above. Three keys used to cost three passes over
# every scope, each behind a `$( )` capture of its own — the same files, read
# the same way, giving the same per-key verdicts.
GATE_OPTION_KEYS=(lane_stop_gate_enabled lane_stop_gate_sentinel lane_stop_gate_marker)
GATE_MANAGED_RESOLVED=0
GATE_USER_RESOLVED=0
GATE_USER_OPT_HAVE=(0 0 0)
GATE_USER_OPT_VALUE=("" "" "")
gate_option_to() {
  local __dest="$1" key="$2" i idx=-1 uf
  for i in "${!GATE_OPTION_KEYS[@]}"; do
    [[ "${GATE_OPTION_KEYS[i]}" == "$key" ]] && idx=$i
  done
  ((idx >= 0)) || return 1
  if ((!GATE_MANAGED_RESOLVED)); then
    GATE_MANAGED_RESOLVED=1
    gate_managed_options_to "${GATE_OPTION_KEYS[@]}" || true
  fi
  if ((GATE_MANAGED_OPT_HAVE[idx])); then
    printf -v "$__dest" '%s' "${GATE_MANAGED_OPT_VALUE[idx]}"
    return 0
  fi
  if [[ -n "$GATE_ARM_JSON" ]]; then
    if [[ "$key" == "lane_stop_gate_enabled" ]]; then
      printf -v "$__dest" 'true'
      return 0
    fi
    if ((GATE_ARM_OPT_HAVE[idx])); then
      printf -v "$__dest" '%s' "${GATE_ARM_OPT_VALUE[idx]}"
      return 0
    fi
  fi
  if ((!GATE_USER_RESOLVED)); then
    GATE_USER_RESOLVED=1
    if gate_user_settings_file_to uf && gate_settings_options_to "$uf" "${GATE_OPTION_KEYS[@]}"; then
      GATE_USER_OPT_HAVE=("${GATE_FILE_OPT_HAVE[@]}")
      GATE_USER_OPT_VALUE=("${GATE_FILE_OPT_VALUE[@]}")
    fi
  fi
  ((GATE_USER_OPT_HAVE[idx])) || return 1
  printf -v "$__dest" '%s' "${GATE_USER_OPT_VALUE[idx]}"
}

gate_option_to ENABLED lane_stop_gate_enabled || ENABLED=""
if [[ "$ENABLED" != "true" ]]; then
  # No trusted source says "on". A trusted explicit false stays silent — that is
  # a configured verdict, not a claim the gate declined to honor. The two ways a
  # gate a lane EXPECTED can end up off get distinct, accurate once-per-session
  # notices instead of a silent disengage:
  if [[ -z "$ENABLED" ]]; then
    if [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" && -z "$GATE_ARM_JSON" ]]; then
      # An arm id reached the hook, but no valid record backs it — spent,
      # TTL-expired, claimed by a different session, or malformed. This is the
      # legitimately-armed-then-stale case; do NOT blame a repo env block.
      if hook::notice_once "autonomy-lane-stop-gate-stale-arm" "$INPUT"; then
        hook::emit_skip_notice "Stop" \
          "autonomy lane-stop gate: this session carries an arm id but no matching arm record is present (it may have expired, been claimed by another session, or been cleaned up), so the gate stays off (#1784). Relaunch the lane through the claude-ops lane launcher to re-arm it."
      fi
    elif [[ "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED:-}" == "true" ]]; then
      # Enablement claimed on the untrusted env channel with no arm id at all —
      # a pre-0.12.0 launcher still delivering over --settings/env, or a repo
      # env block attempting the pre-#1784 attack. Surfacing it beats silence.
      if hook::notice_once "autonomy-lane-stop-gate-untrusted-enable" "$INPUT"; then
        hook::emit_skip_notice "Stop" \
          "autonomy lane-stop gate: enablement was claimed on the environment channel only — no managed/user setting configures it and no arm record matches — so the gate stays off (#1784). A lane launched expecting the gate needs the current claude-ops lane launcher (which arms it at launch); a repository cannot opt sessions in via its own settings.json env block."
      fi
    fi
  fi
  exit 0
fi

# Has completion been explicitly signaled? SIGNAL records which channel fired
# (telemetry vocabulary: sentinel | marker | none — never the token itself).
SIGNALED=0
SIGNAL="none"

# Signal 1 — the sentinel token in the agent's final message. Matched only when
# the token stands alone on its own line (surrounding whitespace allowed), which
# is exactly the "emit the exact token ... on its own line" instruction the block
# reason gives. Requiring a dedicated line — not merely a standalone word — means
# a message that only mentions or negates the token inline (e.g. "I should not
# emit LANE-STOP-OK yet") does not authorize the stop.
# An empty configured sentinel falls back to the default rather than silencing
# the token channel: emptiness is not a documented way to disable it, and the
# block reason below would otherwise instruct the agent to emit an empty token.
gate_option_to SENTINEL lane_stop_gate_sentinel || SENTINEL=""
[[ -n "$SENTINEL" ]] || SENTINEL="LANE-STOP-OK"
# Escape any regex metacharacters in the (configurable) sentinel before use —
# the same fifteen characters the former `sed 's/[][\.^$*+?(){}|/]/\\&/g'`
# escaped, one backslash each, done by the shell.
SENTINEL_RE=""
for ((i = 0; i < ${#SENTINEL}; i++)); do
  c="${SENTINEL:i:1}"
  case "$c" in
  '[' | ']' | "\\" | '.' | '^' | '$' | '*' | '+' | '?' | '(' | ')' | '{' | '}' | '|' | '/') SENTINEL_RE+="\\$c" ;;
  *) SENTINEL_RE+="$c" ;;
  esac
done
# Matched by the shell's own ERE engine (`[[ =~ ]]`), not `grep -qE` over a
# here-string: no process, and no pipeline for an early match to be lost in.
# grep judged one LINE at a time, `^[[:space:]]*TOKEN[[:space:]]*$`; the same
# verdict over the whole message is "TOKEN preceded by start-of-message or a
# newline plus whitespace, followed by whitespace plus a newline or
# end-of-message". The two agree on every message: whitespace never contains
# the token, so the last newline before it and the first after it bound one
# line holding nothing but whitespace and the token, and any such line
# satisfies the pattern in both directions. bash compiles the pattern without
# REG_NEWLINE, so `^` and `$` are message ends here, never line ends, which is
# why the newline alternatives are spelled out.
#
# The one message class where the two engines part: a configured token that
# itself holds a newline. grep read that newline as a pattern separator and
# authorized the stop on a line matching EITHER half of the token; here the
# token is one pattern, so only the whole token standing alone matches, which
# is what the block reason below asks the agent to emit. Disclosed in the
# 0.22.30 changelog entry; no shipped launcher writes such a token.
SENTINEL_LINE_RE="(^|"$'\n'")[[:space:]]*${SENTINEL_RE}[[:space:]]*("$'\n'"|\$)"
if [[ "$LAST" =~ $SENTINEL_LINE_RE ]]; then
  SIGNALED=1
  SIGNAL="sentinel"
fi

# --- Marker consumption ledger ------------------------------------------------
# One marker, one authorized stop. Deleting the marker is the tidy-up, NOT the
# latch: the marker lives in the watched checkout, which the hook may not be
# permitted to write, and a delete the OS refuses would otherwise leave a file
# that satisfies `[[ -f ]]` on a later, unrelated lane run — the cross-run
# bypass consuming the marker exists to close. The durable record therefore
# lives under this plugin's own data directory (gate_data_dir: install-derived
# first, CLAUDE_PLUGIN_DATA fallback only on an unanchored install). The
# fallback reaches nothing but THIS ledger — enablement and the arm record use
# the install-anchored gate_trusted_data_dir — and the marker it gates is an
# agent-writable declaration in the checkout anyway; see gate_data_dir in the
# lib for why a redirected/unwritable fallback degrades to the documented
# "deletion is the only latch" behavior rather than opening a new hole.

# Identity of the file currently at <path>, as "<mtime> <size>", or "" when this
# host's `stat` reports neither. Used to tell a recreated marker apart from the
# consumed one — BEST-EFFORT, and deliberately coarse. Both dialects' portable
# mtime is whole-second, so a marker recreated at the same size within the same
# second (an empty `touch`-style marker is the realistic case) is
# indistinguishable, and stays latched until the marker's NEXT write lands in a
# different second — an mtime does not advance on its own, so the clock passing
# the second is not what clears it. Sub-second and inode spellings would narrow
# that window but are GNU-only, and this identity feeds a GATE: the coarse read
# costs one skipped completion signal, while a wrong "recreated" verdict costs
# the unearned second authorization the ledger exists to prevent. A withheld
# stop is the correct failure direction, so the portable spelling stands.
#
# marker_identity_to <var> <path> writes the identity into <var>. Each rung is
# its own `{ …; } 2>/dev/null` group so the one stat that answers is exec'd
# straight from its substitution's fork; the former single capture around the
# whole `||` ladder forked once more for the same stat.
marker_identity_to() {
  local __id=""
  # portability-ok: GNU-first of a dual-dialect ladder — the BSD `-f` spelling is
  # the next alternative, and a host with neither returns the empty identity this
  # function documents (#1784)
  { __id=$(stat -c '%Y %s' -- "$2"); } 2>/dev/null ||
    # portability-ok: BSD ladder rung paired with GNU `stat -c` above (#1784)
    { __id=$(stat -f '%m %z' -- "$2"); } 2>/dev/null ||
    __id=""
  printf -v "$1" '%s' "$__id"
}

# Ledger path for a marker path. cksum keys the file name (POSIX, present where
# md5sum is not); the recorded path is re-checked on read, so a cksum collision
# costs a miss, never a wrong verdict.
#
# marker_ledger_path_to <var> <path>. The key is the digits of cksum's output
# (checksum and byte count run together), exactly what the former
# `printf | cksum | tr -cd '0-9'` pipeline produced, so an existing ledger
# entry is still found. cksum reads the path from a process substitution
# (printf, no exec) rather than a pipeline in a capture, and the digit filter
# is a parameter expansion, so the key costs two forks where it cost four.
marker_ledger_path_to() {
  local dir key
  gate_data_dir_to dir
  [[ -n "$dir" ]] || return 1
  { key=$(cksum); } < <(printf '%s' "$2") 2>/dev/null || return 1
  key="${key//[^[:digit:]]/}"
  [[ -n "$key" ]] || return 1
  printf -v "$1" '%s/consumed-markers/%s' "$dir" "$key"
}

# Has the file now at <path> already authorized a stop? True when a ledger entry
# names this exact path AND the file has not changed since (or this host cannot
# tell, in which case a marker whose deletion failed stays consumed — the strict
# direction for a gate: it withholds authorization rather than granting it
# twice). A record whose file now reads as a different one is stale and removed,
# so the fresh marker authorizes normally — within the identity read's
# documented coarseness above.
marker_already_consumed() {
  local path="$1" ledger recorded_path="" recorded_id="" current
  marker_ledger_path_to ledger "$path" || return 1
  [[ -f "$ledger" ]] || return 1
  { IFS= read -r recorded_path && IFS= read -r recorded_id; } <"$ledger" 2>/dev/null
  [[ "$recorded_path" == "$path" ]] || return 1
  marker_identity_to current "$path"
  if [[ -n "$current" && -n "$recorded_id" && "$current" != "$recorded_id" ]]; then
    rm -f -- "$ledger" 2>/dev/null
    return 1
  fi
  return 0
}

# Record that the file at <path> has authorized a stop: its path on line 1, its
# identity on line 2. Best-effort — a data directory this hook cannot write
# leaves the deletion as the only latch, which is the behavior that predates
# this ledger.
marker_record_consumed() {
  local path="$1" ledger identity
  marker_ledger_path_to ledger "$path" || return 0
  # `${ledger%/*}`, not `$(dirname …)`: the ledger path always carries the
  # consumed-markers/ segment, so the strip is dirname's answer with no process.
  mkdir -p -- "${ledger%/*}" 2>/dev/null || return 0
  marker_identity_to identity "$path"
  printf '%s\n%s\n' "$path" "$identity" >"$ledger" 2>/dev/null || true
}

# Signal 2 — the completion-marker file. Absolute path used as-is; a relative
# path resolves against the session cwd from the payload. A marker already
# consumed by an earlier stop is not a signal, however long it survives on
# disk. On use it is deleted AND — when the delete did not take — recorded, so
# the next run reads the same verdict the delete was meant to produce.
gate_option_to MARKER lane_stop_gate_marker || MARKER=""
if [[ "$SIGNALED" -eq 0 && -n "$MARKER" ]]; then
  case "$MARKER" in
  /* | [A-Za-z]:[/\\]*) ;;
  *)
    [[ -n "$CWD" ]] && MARKER="${CWD%/}/$MARKER"
    ;;
  esac
  if [[ -f "$MARKER" ]] && ! marker_already_consumed "$MARKER"; then
    SIGNALED=1
    SIGNAL="marker"
    rm -f -- "$MARKER" 2>/dev/null || true
    # The record is written only when the file survived the delete: a marker
    # that is gone cannot resurrect, and an empty ledger is one less thing to
    # keep correct.
    [[ -e "$MARKER" ]] && marker_record_consumed "$MARKER"
  fi
fi

# Completion signaled → this is a legitimate stop. Allow it, silently. The arm
# record is NOT consumed here — the session may /loop into another cycle whose
# stop must still be gated (see the load block).
if [[ "$SIGNALED" -eq 1 ]]; then
  emit_tel "ok" "completion-signaled" "$SIGNAL"
  exit 0
fi

# Already nudged once this stop cluster (stop_hook_active), yet the lane still
# stops without signaling completion → a genuine down/stuck lane. Alert the
# operator (member 4) and ALLOW the stop — blocking again risks a runaway loop,
# and Claude Code hard-caps consecutive Stop blocks regardless. The one bounded
# structural nudge is the mechanism; the notification is the fail-safe handoff.
if [[ "$STOP_ACTIVE" == "true" ]]; then
  BRANCH=""
  if [[ -n "$CWD" ]]; then
    # git alone in the capture, stderr on the group; a failed git leaves BRANCH
    # empty as the old pipeline did. The control-byte strip that `tr -d
    # '\000-\037'` did is a parameter expansion: `[[:cntrl:]]` covers those
    # bytes and DEL, and git refuses every one of them in a ref name, so no
    # branch git can print is changed by either spelling. lane::notify strips
    # C0 bytes again on its own before any sink.
    { BRANCH=$(git -C "$CWD" branch --show-current); } 2>/dev/null || BRANCH=""
    BRANCH="${BRANCH//[[:cntrl:]]/}"
  fi
  LANE="${CWD##*/}"
  [[ -n "$BRANCH" ]] && LANE="$LANE ($BRANCH)"
  [[ -n "$LANE" ]] || LANE="unknown"
  lane::notify "Autonomy lane stopped" \
    "Lane $LANE stopped without signaling completion — it may be down or stuck. Check it."
  emit_tel "ok" "stopped-after-nudge" "none"
  exit 0
fi

# First stop attempt without a completion signal → block once and re-inject the
# completion self-check. This directly counters the fabricated-context-percentage
# premature-stop failure (#576/#577): a self-estimated "~50% context" is not a
# completion condition. Emitted as the documented Stop stdout decision.
REASON="Autonomy lane-stop gate: you attempted to stop, but this lane's completion condition is not yet signaled. A lane that stops itself before its stated goal is met is a bug. Do NOT stop on a self-estimated context percentage, a turn count, or a vague sense that enough was done — none of those is completion. Either (1) continue working toward the lane's stated goal, or (2) if the goal is genuinely and verifiably met, declare completion by emitting the exact token ${SENTINEL} on its own line (or by creating the configured completion-marker file), then stop. This is your one automated nudge; if you stop again without signaling completion, the operator will be alerted that the lane went down."

emit_tel "blocked" "nudged" "none"
jq -nc --arg r "$REASON" '{decision:"block", reason:$r}'
exit 0
