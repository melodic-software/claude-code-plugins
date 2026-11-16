#!/usr/bin/env bash
# SessionStart: keep ${CLAUDE_PLUGIN_DATA}/hook-telemetry-sink.sh, a launcher
# that runs this install's hooks/hook-telemetry-sink.sh. The data directory
# survives plugin updates and the plugin root does not, so the launcher is the
# fixed path HOOK_TELEMETRY_SINK=@session-telemetry and @harness-ops resolve to
# (docs/contracts/hook-telemetry, "Sink path resolution").
#
# The launcher carries the two options the sink reads, session_event_log_dir
# and hook_events_max_bytes, as this install has them, setting or clearing each:
# another plugin's hook runs the launcher with its own environment, which would
# otherwise send its rows to a different root than session-telemetry's own.
#
# Rewritten only when that content changes, through a temp file renamed into
# place, so a symlink at the launcher path is replaced, never followed;
# otherwise only touched, because producers pick the newest launcher when
# several session-telemetry installs keep one. A launcher whose sink is gone (its
# install was removed) deletes itself and exits 0, so a producer moves on to
# the next session-telemetry install.
#
# Beside it, ${CLAUDE_PLUGIN_DATA}/options.json records the options this
# session's hooks run with, the record readers in other plugins resolve the
# record roots from (docs/contracts/session-telemetry-data).
#
# Prints nothing: SessionStart stdout becomes context. Never fails the session.
set -uo pipefail

data="${CLAUDE_PLUGIN_DATA:-}"
root="${CLAUDE_PLUGIN_ROOT:-}"
[[ -n "$data" && -n "$root" ]] || exit 0
data="${data%/}"
target="${root%/}/hooks/hook-telemetry-sink.sh"
[[ -f "$target" ]] || exit 0

# json_str_to <var> <text>: <text> as a JSON string body. Control characters
# other than newline, tab and carriage return are dropped.
json_str_to() {
  local s="$2"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//[$'\x01'-$'\x1f']/}"
  printf -v "$1" '%s' "$s"
}

# options.json (docs/contracts/session-telemetry-data): every
# CLAUDE_PLUGIN_OPTION_* this session's hooks received, keyed by option name,
# plus the plugin root, for a reader that cannot see this plugin's options.
# Same write rule as the launcher: replaced through a rename only on a change.
write_options() {
  local name key value json='{"plugin_root":"' esc current="" tmp first=1 i=0
  local -a names=()
  json_str_to esc "$root"
  json+="$esc\",\"options\":{"
  while IFS= read -r name; do
    [[ "$name" == CLAUDE_PLUGIN_OPTION_* ]] && names+=("$name")
  done < <(compgen -e | LC_ALL=C sort)
  # One tr for every key: ${var,,} needs Bash 4, and these hooks run on 3.2.
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    name="${names[i]}"
    json_str_to value "${!name}"
    i=$((i + 1))
    ((first)) || json+=','
    first=0
    json+="\"$key\":\"$value\""
  done < <(((${#names[@]})) && printf '%s\n' "${names[@]#CLAUDE_PLUGIN_OPTION_}" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  json+=$'}}\n'
  local file="$data/options.json"
  [[ -d "$file" ]] && return 0
  if [[ -f "$file" && ! -L "$file" ]]; then
    IFS= read -r -d '' current <"$file" 2>/dev/null
  fi
  [[ "$current" == "$json" ]] && return 0
  mkdir -p -- "$data" 2>/dev/null || return 0
  tmp=$(mktemp "$data/.options.XXXXXX" 2>/dev/null) || return 0
  { printf '%s' "$json" >"$tmp" 2>/dev/null && mv -f -- "$tmp" "$file" 2>/dev/null; } || rm -f -- "$tmp" 2>/dev/null
}
write_options

launcher="$data/hook-telemetry-sink.sh"
[[ -d "$launcher" ]] && exit 0

printf -v content '#!/usr/bin/env bash\n# Written by session-telemetry refresh-sink-launcher.sh at SessionStart.\ntarget=%q\n' "$target"
for option in CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES; do
  if [[ -n "${!option+set}" ]]; then
    printf -v content '%sexport %s=%q\n' "$content" "$option" "${!option}"
  else
    printf -v content '%sunset %s\n' "$content" "$option"
  fi
done
# shellcheck disable=SC2016  # the launcher's own expansions, written literally
content+='[[ -f "$target" ]] || { rm -f -- "${BASH_SOURCE[0]}"; exit 0; }
exec bash "$target"
'

current=""
if [[ -f "$launcher" && ! -L "$launcher" ]]; then
  IFS= read -r -d '' current <"$launcher" 2>/dev/null
fi
if [[ "$current" == "$content" ]]; then
  touch -- "$launcher" 2>/dev/null
  exit 0
fi

mkdir -p -- "$data" 2>/dev/null || exit 0
tmp=$(mktemp "$data/.hook-telemetry-sink.XXXXXX" 2>/dev/null) || exit 0
{ printf '%s' "$content" >"$tmp" 2>/dev/null && chmod 755 "$tmp" 2>/dev/null &&
  mv -f -- "$tmp" "$launcher" 2>/dev/null; } || rm -f -- "$tmp" 2>/dev/null
exit 0
