#!/usr/bin/env bash
set -uo pipefail

data="${CLAUDE_PLUGIN_DATA:-}"
root="${CLAUDE_PLUGIN_ROOT:-}"
[[ -n "$data" && -n "$root" ]] || exit 0
data="${data%/}"
target="${root%/}/hooks/hook-telemetry-sink.sh"
[[ -f "$target" ]] || exit 0

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

write_options() {
  local name key value json='{"plugin_root":"' esc current="" tmp first=1 i=0
  local -a names=()
  json_str_to esc "$root"
  json+="$esc\",\"options\":{"
  while IFS= read -r name; do
    [[ "$name" == CLAUDE_PLUGIN_OPTION_* ]] && names+=("$name")
  done < <(compgen -e | LC_ALL=C sort)
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
