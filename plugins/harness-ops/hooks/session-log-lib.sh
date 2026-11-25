# GENERATED from plugins/session-telemetry/hooks/session-log-lib.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# shellcheck shell=bash

# shellcheck disable=SC2034 # the lists are read by session-event-log.sh
SLOG_EVENT_LOG_STRINGS="transcript_path cwd scratchpad_dir permission_mode agent_type model trigger memory_type load_reason trigger_file_path parent_file_path expansion_type command_name command_source notification_type agent_transcript_path task_id teammate_name team_name error@StopFailure old_cwd new_cwd directory worktree_path from_model to_model requested_model cache_ttl pricing mcp_server_name mode elicitation_id action"
# shellcheck disable=SC2034
SLOG_EVENT_LOG_SCALARS="seconds_since_last_response context_tokens prompt_cache_likely_expired estimated_cache_write_usd is_interrupt stop_hook_active prompt_cache_warm"
# shellcheck disable=SC2034
SLOG_EVENT_LOG_CONTENT="prompt session_title command_args message title last_assistant_message task_subject task_description error_details custom_instructions compact_summary url error@PostToolUseFailure"
# shellcheck disable=SC2034
SLOG_EFFORT_NA_EVENTS="SessionStart SessionEnd Setup InstructionsLoaded UserPromptSubmit UserPromptExpansion Notification SubagentStart TaskCreated TaskCompleted TeammateIdle ConfigChange CwdChanged DirectoryAdded WorktreeRemove PreCompact PostCompact PreModelSwitch PostModelSwitch Elicitation ElicitationResult"

SLOG_DEFAULT_ROOT=".observability/claude"

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

slog_physical_to() {
  local slog__physical_var="$1" slog__physical_saved="$PWD" slog__physical_path=""
  if cd -P -- "$2" 2>/dev/null; then
    slog__physical_path="$PWD"
    cd -- "$slog__physical_saved" 2>/dev/null || cd / || true
  fi
  printf -v "$slog__physical_var" '%s' "$slog__physical_path"
}

slog_anchor_to() {
  local slog__anchor_var="$1" slog__anchor_dir="${2%/}" slog__anchor_line="" slog__anchor_gitdir
  local slog__anchor_common="" slog__anchor_back="" slog__anchor_phys_gitdir=""
  local slog__anchor_phys_back="" slog__anchor_phys_dir=""
  printf -v "$slog__anchor_var" '%s' "$2"
  [[ -n "$slog__anchor_dir" && -f "$slog__anchor_dir/.git" ]] || return 0
  { IFS= read -r slog__anchor_line || :; } 2>/dev/null <"$slog__anchor_dir/.git"
  slog__anchor_line="${slog__anchor_line%$'\r'}"
  [[ "$slog__anchor_line" == "gitdir: "?* ]] || return 0
  slog__anchor_gitdir="${slog__anchor_line#gitdir: }"
  case "$slog__anchor_gitdir" in
  /* | [A-Za-z]:*) ;;
  *) slog__anchor_gitdir="$slog__anchor_dir/$slog__anchor_gitdir" ;;
  esac
  [[ -f "$slog__anchor_gitdir/commondir" ]] || return 0
  { IFS= read -r slog__anchor_common || :; } 2>/dev/null <"$slog__anchor_gitdir/commondir"
  slog__anchor_common="${slog__anchor_common%$'\r'}"
  [[ -n "$slog__anchor_common" ]] || return 0
  case "$slog__anchor_common" in
  /* | [A-Za-z]:*) ;;
  *) slog__anchor_common="$slog__anchor_gitdir/$slog__anchor_common" ;;
  esac
  slog_physical_to slog__anchor_common "$slog__anchor_common"
  [[ "${slog__anchor_common##*/}" == .git && -n "${slog__anchor_common%/.git}" ]] || return 0
  slog_physical_to slog__anchor_phys_gitdir "$slog__anchor_gitdir"
  [[ "${slog__anchor_phys_gitdir%/*}" == "$slog__anchor_common/worktrees" ]] || return 0
  [[ -f "$slog__anchor_phys_gitdir/gitdir" ]] || return 0
  { IFS= read -r slog__anchor_back || :; } 2>/dev/null <"$slog__anchor_phys_gitdir/gitdir"
  slog__anchor_back="${slog__anchor_back%$'\r'}"
  [[ "$slog__anchor_back" == */.git ]] || return 0
  case "$slog__anchor_back" in
  /* | [A-Za-z]:*) ;;
  *) slog__anchor_back="$slog__anchor_phys_gitdir/$slog__anchor_back" ;;
  esac
  slog_physical_to slog__anchor_phys_back "${slog__anchor_back%/.git}"
  slog_physical_to slog__anchor_phys_dir "$slog__anchor_dir"
  [[ -n "$slog__anchor_phys_back" && "$slog__anchor_phys_back" == "$slog__anchor_phys_dir" ]] || return 0
  printf -v "$slog__anchor_var" '%s' "${slog__anchor_common%/.git}"
}

slog_root_to() {
  local slog__var="$1" slog__project=""
  slog_anchor_to slog__project "$2"
  printf -v "$slog__var" '%s' ""
  local slog__rel="${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR:-$SLOG_DEFAULT_ROOT}"
  slog__rel="${slog__rel%/}"
  slog_contained "$slog__rel" && [[ -n "$slog__project" ]] || return 0
  local slog__abs="${slog__project%/}/$slog__rel"
  local slog__probe="$slog__abs" slog__saved="$PWD" slog__phys_project="" slog__phys_probe=""
  while [[ -n "$slog__probe" && ! -d "$slog__probe" ]]; do
    slog__probe="${slog__probe%/*}"
  done
  [[ -n "$slog__probe" ]] && cd -P -- "$slog__project" 2>/dev/null || return 0
  slog__phys_project="$PWD"
  cd -P -- "$slog__probe" 2>/dev/null && slog__phys_probe="$PWD"
  cd -- "$slog__saved" 2>/dev/null || cd / || true
  [[ "$slog__phys_probe" == "$slog__phys_project" || "$slog__phys_probe" == "$slog__phys_project/"* ]] || return 0
  [[ "$slog__phys_probe" == "$slog__phys_project" && "$slog__probe" == "$slog__abs" ]] && return 0
  printf -v "$slog__var" '%s' "$slog__abs"
}

slog_in_checkout() {
  [[ -d "$1/.git" || -f "$1/.git" ]]
}

slog_guard_ok() {
  local slog__root="$1" slog__project="$2" slog__line slog__try slog__other slog__comment
  slog_in_checkout "$slog__project" || return 0
  for ((slog__try = 0; slog__try < 5; slog__try++)); do
    if [[ ! -f "$slog__root/.gitignore" ]]; then
      mkdir -p "$slog__root" 2>/dev/null || return 1
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
    ((slog__other || slog__comment)) && return 1
    if [[ -s "$slog__root/.gitignore" ]]; then
      continue
    fi
    printf '*\n' >>"$slog__root/.gitignore" 2>/dev/null || return 1
    return 0
  done
  return 1
}

slog_valid_id() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# printf %(fmt)T needs bash 4.2:
# https://tiswww.case.edu/php/chet/bash/NEWS
slog_ts_to() {
  local slog__ts=""
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
    TZ=UTC printf -v slog__ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
  else
    slog__ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  fi
  printf -v "$1" '%s' "$slog__ts"
}

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

SLOG_CTRL=$'\001\002\003\004\005\006\007\010\013\014\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037'

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

slog_append_capped() {
  local slog__f="$1" slog__l="$2" slog__max="$3"
  [[ "$slog__max" =~ ^[1-9][0-9]{0,17}$ ]] || slog__max=10485760
  if command -v flock >/dev/null 2>&1; then
    (
      if flock -w 2 9; then
        slog__append_over_cap "$slog__f" "$slog__l" "$slog__max"
      else
        printf '%s\n' "$slog__l" >>"$slog__f"
      fi
    ) 9>"${slog__f}.lock" 2>/dev/null
  else
    slog__append_over_cap "$slog__f" "$slog__l" "$slog__max" 2>/dev/null
  fi
  return 0
}

slog__append_over_cap() {
  local slog__size
  slog__size=$(wc -c <"$1" 2>/dev/null) || slog__size=0
  ((slog__size > $3)) && mv -f "$1" "$1.1" 2>/dev/null
  printf '%s\n' "$2" >>"$1"
}

slog_lock() {
  local slog__was=0 slog__rc=0
  [[ $- == *C* ]] && slog__was=1
  set -C
  { printf '%s' "$2" >"$1"; } 2>/dev/null || slog__rc=1
  ((slog__was)) || set +C
  return "$slog__rc"
}

slog_unlock() {
  local slog__cur=""
  IFS= read -r slog__cur 2>/dev/null <"$1"
  [[ "$slog__cur" == "$2" ]] && rm -f "$1" 2>/dev/null
  return 0
}

slog_byte_len_to() {
  local LC_ALL=C
  printf -v "$1" '%s' "${#2}"
}

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

slog_category_enabled() {
  local slog__want="${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES:-}" slog__c
  [[ -n "$slog__want" ]] || return 0
  slog__want="${slog__want//,/ }"
  for slog__c in $slog__want; do
    [[ "$slog__c" == "$1" ]] && return 0
  done
  return 1
}
