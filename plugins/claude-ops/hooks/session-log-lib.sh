# shellcheck shell=bash
# Shared by the per-session hook event log (session-event-log.sh), the
# SessionEnd retention hook (session-retention.sh), the telemetry sink
# (hook-telemetry-sink.sh) and the skill-usage store writer
# (claude-ops-paths.sh): where the log root is, whether a configured root is
# contained, the self-ignoring guard that keeps the tree out of `git status`,
# and the one record formatter every JSONL writer here emits through. Sourced,
# never executed (no shebang, like every other sourced library here).
# Deliberately NOT lib/hook-utils.sh: a logging producer runs on every hook
# event, and parsing that library costs more than the rest of the hook
# (docs/topics/hook-logging-pipeline, Brief Q15). Nothing here spawns a
# process; every function assigns into a caller-named variable (`printf -v`)
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
#   source: "event-log"      category, plus prompt_id, tool_use_id, agent_id,
#                            tool_name, file_path, reason and traceparent when
#                            the payload carried them — one hook EVENT the
#                            session saw, written by session-event-log.sh;
#                            no `hook`, because no hook run is described and
#                            `duration_ms` is the logger's own cost
#
# `source` is the discriminator: a reader selects hook runs with
# `.source == "envelope"` (equivalently `.hook != null`) and the event timeline
# with `.source == "event-log"`. The skill-usage store is a SEPARATE contract
# with its own readers (skills/audit-skill-visibility); it shares the formatter
# and the escaping, not this key set.

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
slog_guard_ok() {
  local slog__root="$1" slog__project="$2" slog__line
  slog_in_checkout "$slog__project" || return 0
  if [[ -f "$slog__root/.gitignore" ]]; then
    while IFS= read -r slog__line || [[ -n "$slog__line" ]]; do
      slog__line="${slog__line%$'\r'}"
      case "$slog__line" in
      '' | '#'*) continue ;;
      '*') return 0 ;;
      *) return 1 ;;
      esac
    done <"$slog__root/.gitignore"
    # Content but no `*` line (comments only): an operator's file, refused.
    # No content at all: a sibling producer opened the file a moment ago and
    # has not written its byte yet (33 hooks fire on one event), or a crash
    # left it empty; either way the `*` write below is what it needs, and two
    # writers of the same two bytes cannot disagree.
    [[ -s "$slog__root/.gitignore" ]] && return 1
  else
    mkdir -p "$slog__root" 2>/dev/null || return 1
  fi
  printf '*\n' >"$slog__root/.gitignore" 2>/dev/null || return 1
  return 0
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
