# shellcheck shell=bash
# Shared by the per-session hook event log (session-event-log.sh), the
# SessionEnd retention hook (session-retention.sh), the telemetry sink
# (hook-telemetry-sink.sh) and the skill-usage store writer
# (harness-ops-paths.sh): where the log root is, whether a configured root is
# contained, the self-ignoring guard that keeps the tree out of `git status`,
# and the one record formatter every JSONL writer here emits through. Sourced,
# never executed (no shebang, like every other sourced library here).
# Deliberately NOT lib/hook-utils.sh: a logging producer runs on every hook
# event, and parsing that library costs more than the rest of the hook.
# Nothing here spawns a
# process, except slog_append on a locked line (`rm`, and `sleep` while it
# waits for the lock); every other function assigns into a caller-named variable (`printf -v`)
# or returns a status. Locals carry a `slog__` prefix so `printf -v` can never
# land on a shadowed name.
#
# THE HOOK EVENT RECORD (slog_event_record_to) is the single key set every
# reader of the log root queries. One event key, `hook_event_name`, on every
# route, so no reader reconciles `.event // .hook_event_name`:
#
#   spine, on every record   ts, hook_event_name, status, duration_ms, source
#                            session_id (omitted only where the writer has
#                            none: the shared hook-events.jsonl route)
#   source: "envelope"       hook, exit_code, subject, tool, and changed when
#                            the producer sent a rewrite verdict — a hook run,
#                            written by hook-telemetry-sink.sh on both routes
#   source: "event-log"      category and effort, plus prompt_id, tool_use_id,
#                            agent_id, tool_name, file_path, reason,
#                            traceparent and the SLOG_EVENT_LOG_STRINGS and
#                            SLOG_EVENT_LOG_SCALARS keys below when the
#                            payload carried them — one hook EVENT the
#                            session saw, written by session-event-log.sh;
#                            no `hook`, because no hook run is described and
#                            `duration_ms` is the logger's own cost
#
# `source` is the discriminator: a reader selects hook runs with
# `.source == "envelope"` (equivalently `.hook != null`) and the event timeline
# with `.source == "event-log"`. The skill-usage store is a SEPARATE contract
# with its own readers (skills/audit-skill-visibility); it shares the formatter
# and the escaping, not this key set.

# THE EVENT-LOG METADATA ALLOWLIST. The payload keys an event-log record copies
# when they sit at the payload's top level: string enums, ids, names and paths
# (STRINGS, re-emitted as the payload's own JSON string bodies) and booleans and
# numbers (SCALARS, emitted with their JSON type). Paths are recorded as the
# payload's raw absolute values; `file_path` keeps its own reduction in the
# hook. A `key@Event` entry is read only on that event: `error` is an enum on
# StopFailure and tool output on PostToolUseFailure. Content strings
# (SLOG_EVENT_LOG_CONTENT) are copied only when the session_event_log_content
# option is true. Never copied: every object or array, tool_input and
# tool_response among them, and the payload keys `source` and `duration_ms`,
# whose names the record's spine already holds.
#
# `effort` is on every event-log record: the level, `n/a` on the events in
# SLOG_EFFORT_NA_EVENTS, `unset` when an event that can carry a level did not.
# The logged events outside that list (PermissionRequest, PermissionDenied,
# PostToolUseFailure, PostToolBatch, Stop, SubagentStop, StopFailure) are built
# from a tool-use context, the only source of the payload's effort object, and
# Claude Code sets a hook's $CLAUDE_EFFORT from that object alone. So the
# payload's level is recorded first; $CLAUDE_EFFORT fills in only when the
# payload has no effort object, and an inherited value never overrides it.
#
# Claim: these keys, their types and the events carrying them are the hooks
# reference's common input fields and per-event input sections; `effort` is
# present only on events fired within a tool-use context, and a hook's
# $CLAUDE_EFFORT is the payload's effort.level, so both are empty on the
# SLOG_EFFORT_NA_EVENTS events.
# Basis: https://code.claude.com/docs/en/hooks ("Common input fields" and each
# event's "input" section); the page does not say which events, so the event
# split is read from the Claude Code 2.1.287 binary (the hook-input builder
# and the hook spawn environment).
# As of: 2026-10-02.
# Recheck: each /harness-ops:changelog ingest whose release notes touch hook
# input fields, when a key here stops appearing in the page's input sections,
# or when Stop rows on an effort-capable model record `unset`.
# shellcheck disable=SC2034 # the lists are read by session-event-log.sh
SLOG_EVENT_LOG_STRINGS="transcript_path cwd scratchpad_dir permission_mode agent_type model trigger memory_type load_reason trigger_file_path parent_file_path expansion_type command_name command_source notification_type agent_transcript_path task_id teammate_name team_name error@StopFailure old_cwd new_cwd directory worktree_path from_model to_model requested_model cache_ttl pricing mcp_server_name mode elicitation_id action"
# shellcheck disable=SC2034
SLOG_EVENT_LOG_SCALARS="seconds_since_last_response context_tokens prompt_cache_likely_expired estimated_cache_write_usd is_interrupt stop_hook_active prompt_cache_warm"
# shellcheck disable=SC2034
SLOG_EVENT_LOG_CONTENT="prompt session_title command_args message title last_assistant_message task_subject task_description error_details custom_instructions compact_summary url error@PostToolUseFailure"
# shellcheck disable=SC2034
SLOG_EFFORT_NA_EVENTS="SessionStart SessionEnd Setup InstructionsLoaded UserPromptSubmit UserPromptExpansion Notification SubagentStart TaskCreated TaskCompleted TeammateIdle ConfigChange CwdChanged DirectoryAdded WorktreeRemove PreCompact PostCompact PreModelSwitch PostModelSwitch Elicitation ElicitationResult"

# Default log root, project-relative. Overridden by the session_event_log_dir
# userConfig option (CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR).
SLOG_DEFAULT_ROOT=".observability/claude"

# slog_contained <relative-path>: 0 when the path is a contained relative path
# (no leading slash, drive or UNC prefix, no `..` segment with either separator,
# no leading `~`), 1 otherwise. Same rule the skill-usage store applies.
slog_contained() {
  local slog__p="$1"
  [[ -n "$slog__p" ]] || return 1
  case "$slog__p" in
  /* | ~* | [A-Za-z]:*) return 1 ;;
  *) ;;
  esac
  [[ "$slog__p" == *\\* ]] && return 1
  case "/$slog__p/" in
  */../* | */./*) return 1 ;;
  *) ;;
  esac
  return 0
}

# slog_root_to <var> <project-dir>: the absolute log root for <project-dir>,
# or the empty string when the configured root is uncontained or resolves to
# the project root itself (a `*` guard there would ignore the whole repository).
#
# Containment is checked twice: lexically (slog_contained) and physically. A
# relative path whose existing component is a symlink can point anywhere, and
# the retention hook deletes under this root, so the nearest existing ancestor
# of the root is resolved with `cd -P` (a builtin; no process) and must sit
# below the physically resolved project. A root that exists and resolves to
# the project itself is refused for the same reason `.` is.
slog_root_to() {
  local slog__var="$1" slog__project="$2"
  local slog__rel="${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR:-$SLOG_DEFAULT_ROOT}"
  slog__rel="${slog__rel%/}"
  if ! slog_contained "$slog__rel" || [[ -z "$slog__project" ]]; then
    printf -v "$slog__var" '%s' ""
    return 0
  fi
  local slog__abs="${slog__project%/}/$slog__rel"
  local slog__probe="$slog__abs" slog__saved="$PWD" slog__phys_project="" slog__phys_probe=""
  while [[ -n "$slog__probe" && ! -d "$slog__probe" ]]; do
    slog__probe="${slog__probe%/*}"
  done
  if [[ -z "$slog__probe" ]] || ! cd -P -- "$slog__project" 2>/dev/null; then
    printf -v "$slog__var" '%s' ""
    return 0
  fi
  slog__phys_project="$PWD"
  if cd -P -- "$slog__probe" 2>/dev/null; then
    slog__phys_probe="$PWD"
  fi
  cd -- "$slog__saved" 2>/dev/null || cd / || true
  if [[ -z "$slog__phys_probe" ]] ||
    [[ "$slog__phys_probe" != "$slog__phys_project" && "$slog__phys_probe" != "$slog__phys_project/"* ]] ||
    [[ "$slog__phys_probe" == "$slog__phys_project" && "$slog__probe" == "$slog__abs" ]]; then
    printf -v "$slog__var" '%s' ""
    return 0
  fi
  printf -v "$slog__var" '%s' "$slog__abs"
}

# slog_in_checkout <project-dir>: 0 when the project is a git checkout (a .git
# directory, or the .git file a worktree carries). No git spawn.
slog_in_checkout() {
  [[ -d "$1/.git" || -f "$1/.git" ]]
}

# slog_guard_ok <root> <project-dir>: make sure nothing written under <root>
# can show up as an untracked file. Inside a checkout the root must carry a
# self-ignoring .gitignore whose first non-comment line is `*`; one is created
# (announced through the observability report, never here) when absent, and a
# present-but-different one is left alone and refuses the write, because an
# operator edited it. Outside a checkout there is nothing to keep clean, so the
# write proceeds without a guard. Returns 0 when writing is allowed.
#
# A fresh guard is created with an exclusive open, so a sibling's file stays
# intact. The new file is empty until its two bytes land. A reader that
# samples that window and then finds the file non-empty reads it again; those
# bytes are `*`. An operator's text is stable across that reread, so it is
# still refused. Refusing the first sample drops the event: 33 hooks on one
# fresh guard were landing 32 lines.
slog_guard_ok() {
  local slog__root="$1" slog__project="$2" slog__line slog__try slog__other slog__comment
  slog_in_checkout "$slog__project" || return 0
  for ((slog__try = 0; slog__try < 5; slog__try++)); do
    if [[ ! -f "$slog__root/.gitignore" ]]; then
      mkdir -p "$slog__root" 2>/dev/null || return 1
      # Exclusive create. A truncating `>` would empty a file a sibling has
      # already opened, and that sibling would then miss the `*` line.
      if (set -o noclobber; printf '*\n' >"$slog__root/.gitignore") 2>/dev/null; then
        return 0
      fi
      continue
    fi
    slog__other=0
    slog__comment=0
    while IFS= read -r slog__line || [[ -n "$slog__line" ]]; do
      slog__line="${slog__line%$'\r'}"
      case "$slog__line" in
      '') continue ;;
      '#'*) slog__comment=1 ;;
      '*') return 0 ;;
      *)
        slog__other=1
        break
        ;;
      esac
    done <"$slog__root/.gitignore"
    if ((slog__other)); then
      return 1
    fi
    # Comments and no `*`: an operator's file. A healed guard is a `*` line,
    # so this refusal does not wait for another pass.
    if ((slog__comment)); then
      return 1
    fi
    if [[ -s "$slog__root/.gitignore" ]]; then
      # The read saw no line and the file now has bytes: a sibling finished
      # writing `*` after this read opened it.
      continue
    fi
    # Empty: a sibling created it and has not written, or a crash left it
    # empty. Append the two bytes every healer writes. Append leaves a
    # sibling's `*` in place, and a file of repeated `*` lines still allows
    # the write.
    printf '*\n' >>"$slog__root/.gitignore" 2>/dev/null || return 1
    return 0
  done
  return 1
}

# slog_valid_id <value>: 0 when <value> is a safe file-name component
# (Claude Code session and agent ids are UUID-shaped; nothing else is admitted
# because the value names a file under the log root).
slog_valid_id() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# slog_ts_to <var>: UTC timestamp, second resolution, without a process on Bash
# 4.2+ (printf %()T); `date` on older shells.
slog_ts_to() {
  local slog__ts=""
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
    TZ=UTC printf -v slog__ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
  else
    slog__ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  fi
  printf -v "$1" '%s' "$slog__ts"
}

# slog_duration_ms_to <var> <start-epochrealtime>: whole milliseconds since
# <start>, or the empty string when EPOCHREALTIME is unavailable (Bash < 5).
slog_duration_ms_to() {
  local slog__var="$1" slog__start="$2" slog__now="${EPOCHREALTIME:-}"
  if [[ -z "$slog__start" || -z "$slog__now" ]]; then
    printf -v "$slog__var" '%s' ""
    return 0
  fi
  local slog__s0="${slog__start%%.*}" slog__f0="${slog__start#*.}"
  local slog__s1="${slog__now%%.*}" slog__f1="${slog__now#*.}"
  slog__f0="${slog__f0}000000"
  slog__f1="${slog__f1}000000"
  local slog__us=$(((10#$slog__s1 - 10#$slog__s0) * 1000000 + 10#${slog__f1:0:6} - 10#${slog__f0:0:6}))
  ((slog__us < 0)) && slog__us=0
  printf -v "$slog__var" '%s' "$((slog__us / 1000))"
}

# The control characters JSON must escape that have no short form below. NUL
# cannot appear in a bash variable, so it is not a member.
SLOG_CTRL=$'\001\002\003\004\005\006\007\010\013\014\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037'

# slog_json_escape_to <var> <value>: <value> as a JSON string BODY (the bytes
# that go between the quotes). Pure parameter expansion for the four common
# cases; a value carrying another control character takes one bounded loop.
# This is the only escaping path for a decoded value in this plugin's writers,
# so a subject holding a quote, a backslash or a tab cannot produce a line the
# reader's `jq -s` rejects for the whole file.
slog_json_escape_to() {
  local slog__var="$1" slog__s="$2" slog__out slog__ch slog__i
  slog__s="${slog__s//\\/\\\\}"
  slog__s="${slog__s//\"/\\\"}"
  slog__s="${slog__s//$'\n'/\\n}"
  slog__s="${slog__s//$'\r'/\\r}"
  slog__s="${slog__s//$'\t'/\\t}"
  case "$slog__s" in
  *["$SLOG_CTRL"]*)
    slog__out=""
    for ((slog__i = 0; slog__i < ${#slog__s}; slog__i++)); do
      slog__ch="${slog__s:slog__i:1}"
      case "$slog__ch" in
      ["$SLOG_CTRL"]) printf -v slog__ch '\\u%04x' "'$slog__ch" ;;
      *) ;;
      esac
      slog__out+="$slog__ch"
    done
    slog__s="$slog__out"
    ;;
  *) ;;
  esac
  printf -v "$slog__var" '%s' "$slog__s"
}

# slog_record_to <var> [<key> <type> <value>]...: one compact JSON object, the
# `jq -c` shape, built from builtins alone. Keys are emitted in the order given
# and every triple emits, so presence is the caller's decision, not a guess
# made here. Types:
#
#   s  a decoded string; escaped here (slog_json_escape_to) and quoted
#   b  a JSON string BODY already escaped by the document it came from
#      (session-event-log.sh re-emits the payload's own bodies rather than
#      re-deriving an escape it has no jq to check)
#   n  a raw JSON scalar: an integer, a decimal, true, false. Anything else,
#      the empty string included, is emitted as null rather than as a token
#      that would make the line unparsable.
slog_record_to() {
  local slog__var="$1" slog__line="{" slog__sep="" slog__key slog__type slog__val slog__rendered
  shift
  while (($# >= 3)); do
    slog__key="$1"
    slog__type="$2"
    slog__val="$3"
    shift 3
    case "$slog__type" in
    s)
      slog_json_escape_to slog__rendered "$slog__val"
      slog__rendered="\"$slog__rendered\""
      ;;
    b) slog__rendered="\"$slog__val\"" ;;
    n)
      if [[ "$slog__val" =~ ^-?[0-9]+(\.[0-9]+)?$ || "$slog__val" == "true" || "$slog__val" == "false" ]]; then
        slog__rendered="$slog__val"
      else
        slog__rendered="null"
      fi
      ;;
    *) continue ;;
    esac
    slog__line+="${slog__sep}\"$slog__key\":$slog__rendered"
    slog__sep=","
  done
  printf -v "$slog__var" '%s' "${slog__line}}"
}

# slog_append <file> <line> [lock]: appends <line> and a newline; always
# returns 0. Bash's printf writes in 4096-byte chunks, so a longer line is
# several write() calls, and any appender that skips the lock can land inside
# one. A line goes under the lock file <file>.lock when it is over 4000 bytes
# or when the caller passes `lock` (session-event-log.sh does whenever content
# fields are on, so its short rows wait for a long one too); otherwise it is
# the single unlocked write it always was, with nothing spawned.
#
# The lock holds the owner's token, and only the owner removes it. A waiter
# polls every 0.05 s. A lock whose token stays the same for 100 polls (5 s or
# more; a 64 KB append takes milliseconds) is stale and is removed, but only
# while it still holds that token. After 200 polls (10 s or more) without the
# lock, the line is appended unlocked, the one path that can still interleave,
# so a hook never drops its row or holds up the session for longer.
slog_append() {
  local slog__f="$1" slog__l="$2" slog__lock="$1.lock" slog__bytes slog__token
  local slog__seen="" slog__cur slog__same=0 slog__n=0 slog__held=0
  slog_byte_len_to slog__bytes "$slog__l"
  if [[ "${3:-}" != lock ]] && ((slog__bytes <= 4000)); then
    printf '%s\n' "$slog__l" >>"$slog__f" 2>/dev/null
    return 0
  fi
  slog__token="$$.$RANDOM$RANDOM"
  while ((slog__n++ < 200)); do
    if slog_lock "$slog__lock" "$slog__token"; then
      slog__held=1
      break
    fi
    slog__cur=""
    IFS= read -r slog__cur 2>/dev/null <"$slog__lock"
    if [[ "$slog__cur" != "$slog__seen" ]]; then
      slog__seen="$slog__cur"
      slog__same=0
    elif ((++slog__same >= 100)); then
      slog_unlock "$slog__lock" "$slog__seen"
      slog__same=0
    fi
    sleep 0.05 2>/dev/null
  done
  printf '%s\n' "$slog__l" >>"$slog__f" 2>/dev/null
  ((slog__held)) && slog_unlock "$slog__lock" "$slog__token"
  return 0
}

# slog_lock <path> <token>: 0 when this call created <path>, writing <token>
# into it. noclobber makes the `>` an O_EXCL create, so exactly one racer
# wins, with no process spawned. Not mkdir: uutils mkdir 0.10.0 was caught
# exiting 0 on EEXIST under contention.
slog_lock() {
  local slog__was=0 slog__rc=0
  [[ $- == *C* ]] && slog__was=1
  set -C
  { printf '%s' "$2" >"$1"; } 2>/dev/null || slog__rc=1
  ((slog__was)) || set +C
  return "$slog__rc"
}

# slog_unlock <path> <token>: removes <path> only while it holds <token>.
slog_unlock() {
  local slog__cur=""
  IFS= read -r slog__cur 2>/dev/null <"$1"
  [[ "$slog__cur" == "$2" ]] && rm -f "$1" 2>/dev/null
  return 0
}

# slog_byte_len_to <var> <string>: the string's length in bytes, not characters.
slog_byte_len_to() {
  local LC_ALL=C
  printf -v "$1" '%s' "${#2}"
}

# slog_event_record_to <var> <source> <ts> <session_id> <hook_event_name>
#                      <status> <duration_ms> [<key> <type> <value>]...
# One hook event record in the key set documented at the top of this file: the
# spine first, in a fixed order, then the route's own keys. `session_id` is the
# one spine key that is omitted when the writer has none, because the shared
# hook-events.jsonl route carries no session by definition; an empty
# `duration_ms` lands as null, which is what an unmeasurable run reports.
slog_event_record_to() {
  local slog__ev_var="$1"
  local -a slog__ev_sid=()
  [[ -n "$4" ]] && slog__ev_sid=(session_id s "$4")
  slog_record_to "$slog__ev_var" \
    ts s "$3" \
    ${slog__ev_sid[@]+"${slog__ev_sid[@]}"} \
    hook_event_name s "$5" \
    status s "$6" \
    duration_ms n "$7" \
    source s "$2" \
    ${8+"${@:8}"}
}

# slog_category_to <var> <hook-event-name>: the category a documented event
# belongs to; the same table the generated registry carries (Phase 4 of the
# topic plan), pinned by the registry's own test.
slog_category_to() {
  local slog__c
  case "$2" in
  SessionStart | SessionEnd | Setup) slog__c=session ;;
  UserPromptSubmit | UserPromptExpansion) slog__c=prompt ;;
  PreToolUse | PostToolUse | PostToolUseFailure | PostToolBatch) slog__c=tool ;;
  PermissionRequest | PermissionDenied) slog__c=permission ;;
  SubagentStart | SubagentStop | TeammateIdle) slog__c=agent ;;
  TaskCreated | TaskCompleted) slog__c=task ;;
  Stop | StopFailure | Notification) slog__c=turn ;;
  InstructionsLoaded | ConfigChange | CwdChanged | DirectoryAdded | FileChanged) slog__c=config ;;
  WorktreeCreate | WorktreeRemove) slog__c=worktree ;;
  PreCompact | PostCompact) slog__c=compaction ;;
  PreModelSwitch | PostModelSwitch) slog__c=model ;;
  Elicitation | ElicitationResult) slog__c=mcp ;;
  MessageDisplay) slog__c=display ;;
  *) slog__c=other ;;
  esac
  printf -v "$1" '%s' "$slog__c"
}

# slog_category_enabled <category>: 0 unless the session_event_log_categories
# option is set and does not list <category> (comma or space separated).
slog_category_enabled() {
  local slog__want="${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES:-}" slog__c
  [[ -n "$slog__want" ]] || return 0
  slog__want="${slog__want//,/ }"
  for slog__c in $slog__want; do
    [[ "$slog__c" == "$1" ]] && return 0
  done
  return 1
}
