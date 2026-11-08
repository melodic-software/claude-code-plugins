#!/usr/bin/env bash
# SessionStart: keep ${CLAUDE_PLUGIN_DATA}/hook-telemetry-sink.sh, a launcher
# that runs this install's hooks/hook-telemetry-sink.sh. The data directory
# survives plugin updates and the plugin root does not, so the launcher is the
# fixed path HOOK_TELEMETRY_SINK=@harness-ops resolves to
# (docs/contracts/hook-telemetry, "Sink path resolution").
#
# The launcher carries the two options the sink reads, session_event_log_dir
# and hook_events_max_bytes, as this install has them, setting or clearing each:
# another plugin's hook runs the launcher with its own environment, which would
# otherwise send its rows to a different root than harness-ops' own.
#
# Rewritten only when that content changes, through a temp file renamed into
# place, so a symlink at the launcher path is replaced, never followed. A
# launcher whose sink is gone (its install was removed) deletes itself and
# exits 0, so a producer moves on to the next harness-ops install.
#
# Prints nothing: SessionStart stdout becomes context. Never fails the session.
set -uo pipefail

data="${CLAUDE_PLUGIN_DATA:-}"
root="${CLAUDE_PLUGIN_ROOT:-}"
[[ -n "$data" && -n "$root" ]] || exit 0
data="${data%/}"
target="${root%/}/hooks/hook-telemetry-sink.sh"
[[ -f "$target" ]] || exit 0
launcher="$data/hook-telemetry-sink.sh"
[[ -d "$launcher" ]] && exit 0

printf -v content '#!/usr/bin/env bash\n# Written by harness-ops refresh-sink-launcher.sh at SessionStart.\ntarget=%q\n' "$target"
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
[[ "$current" == "$content" ]] && exit 0

mkdir -p -- "$data" 2>/dev/null || exit 0
tmp=$(mktemp "$data/.hook-telemetry-sink.XXXXXX" 2>/dev/null) || exit 0
if printf '%s' "$content" >"$tmp" 2>/dev/null && chmod 755 "$tmp" 2>/dev/null &&
  mv -f -- "$tmp" "$launcher" 2>/dev/null; then
  exit 0
fi
rm -f -- "$tmp" 2>/dev/null
exit 0
