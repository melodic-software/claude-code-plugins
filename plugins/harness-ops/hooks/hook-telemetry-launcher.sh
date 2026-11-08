#!/usr/bin/env bash
# SessionStart: write <root>/hook-telemetry-sink.sh, a launcher that execs this
# plugin's installed hook-telemetry-sink.sh, so a repository wires its hook
# producers to the reference sink by a relative path, with no copy in the
# repository:
#   "env": { "HOOK_TELEMETRY_SINK": ".observability/claude/hook-telemetry-sink.sh" }
# <root> is the hook log root (slog_root_to in session-log-lib.sh), so the
# launcher sits under the root's self-ignoring .gitignore and stays out of
# `git status`.
#
# The wiring is the opt-in: the launcher is written only when
# HOOK_TELEMETRY_SINK names <root>/hook-telemetry-sink.sh relative to the
# repository root, so a repository that wires no sink, or its own, gets no file. It is
# rewritten when its text would change: after a plugin update moves the
# install, or when session_event_log_dir or hook_events_max_bytes changes.
# Those two options are written into the launcher because a producer in
# another plugin runs the sink without this plugin's CLAUDE_PLUGIN_OPTION_*
# variables.
#
# Writes nothing to stdout and always exits 0. When no launcher is written, the
# producer finds no sink and drops the event, which it already does for any
# sink that fails.
set -uo pipefail

want="${HOOK_TELEMETRY_SINK:-}"
want="${want#./}"
[[ -n "$want" && -n "${CLAUDE_PROJECT_DIR:-}" ]] || exit 0

# Hook directory by parameter expansion, never `dirname` (a fork; see
# hook-telemetry-sink.sh).
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=session-log-lib.sh
source "$HOOK_DIR/session-log-lib.sh"

# The repository root, resolved as the sink and hook::emit_telemetry resolve
# it, so a session started in a subdirectory still writes where producers look.
project=""
hook::repo_root_to project "$CLAUDE_PROJECT_DIR" || :
project="${project%/}"
[[ -n "$project" ]] || exit 0
root=""
slog_root_to root "$project"
[[ -n "$root" && "$want" == "${root#"$project"/}/hook-telemetry-sink.sh" ]] || exit 0
slog_guard_ok "$root" "$project" || exit 0

# The sink's physical path: `cd -P` is a builtin, and on Git Bash $PWD is the
# /c/... form bash takes as a script argument.
cd -P -- "$HOOK_DIR" 2>/dev/null || exit 0
printf -v target '%q' "$PWD/hook-telemetry-sink.sh"
body='#!/usr/bin/env bash
# Written by harness-ops at session start (hooks/hook-telemetry-launcher.sh);
# rewritten when the plugin moves. Edits here are overwritten.'
for opt in SESSION_EVENT_LOG_DIR HOOK_EVENTS_MAX_BYTES; do
  var="CLAUDE_PLUGIN_OPTION_$opt"
  [[ -n "${!var:-}" ]] || continue
  printf -v value '%q' "${!var}"
  body+=$'\n'"export $var=$value"
done
# shellcheck disable=SC2016 # $BASH is the launcher's own, expanded when it runs
body+=$'\n''exec "$BASH" '"$target"

launcher="$root/hook-telemetry-sink.sh"
current=""
[[ -f "$launcher" ]] && IFS= read -r -d '' current <"$launcher"
[[ "$current" == "$body"$'\n' && -x "$launcher" ]] && exit 0

[[ -d "$root" ]] || mkdir -p "$root" 2>/dev/null || exit 0
tmp="$launcher.$$"
if printf '%s\n' "$body" >"$tmp" 2>/dev/null && chmod +x "$tmp" 2>/dev/null; then
  mv -f "$tmp" "$launcher" 2>/dev/null || rm -f "$tmp" 2>/dev/null
else
  rm -f "$tmp" 2>/dev/null
fi
exit 0
