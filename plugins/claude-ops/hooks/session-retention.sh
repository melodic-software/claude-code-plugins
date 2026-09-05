#!/usr/bin/env bash
# SessionEnd retention for the per-session hook event log
# (<root>/sessions/<session_id>.jsonl, written by session-event-log.sh and the
# telemetry sink). Keeps the newer of the last N sessions or the last D days
# (session_log_keep_sessions, default 30; session_log_keep_days, default 14):
# a file survives when it is among the newest N OR younger than D days.
#
# Budget: SessionEnd hooks get 1.5 s by default, and a plugin-provided timeout
# cannot raise it (Hooks reference, SessionEnd), so this hook does the least
# possible: FOUR processes on a run that prunes (a sweep of stale pending
# directories, one `ls -t` for recency, one `find` for age, one `mv` or `rm`
# over the whole doomed set), and it never reads stdin. The payload is not
# needed, and on a Win32 pipe a read waits out its timeout before returning.
#
# Prune means delete, with one extensibility point: when
# session_log_pre_prune_command is set, the doomed files are MOVED into
# <root>/prune-pending/<epoch>-<pid>/ (one rename each, atomic on one
# filesystem) and the command is spawned fully detached with that directory
# as its one argument, so a slow or failing archiver can neither delay this
# hook nor lose the files; the directory is deleted by a later run once it is
# older than 24 h. Without a command the doomed files are unlinked directly.
# Either way the sessions/ directory is pruned inside this run.
#
# Same kill switch as the producer: retention of a log nobody writes is
# meaningless, and an operator who turned logging off expects nothing to
# happen. Sources session-log-lib.sh only, never hook-utils.sh.
#
# Kill switch: CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED (default false).

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED:-false}" == "true" ]] || exit 0

# shellcheck source=session-log-lib.sh
source "${BASH_SOURCE[0]%/*}/session-log-lib.sh"

keep_n="${CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_SESSIONS:-30}"
keep_days="${CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_DAYS:-14}"
[[ "$keep_n" =~ ^[0-9]+$ ]] && ((keep_n >= 1)) || keep_n=30
[[ "$keep_days" =~ ^[0-9]+$ ]] && ((keep_days >= 1)) || keep_days=14
pre_prune="${CLAUDE_PLUGIN_OPTION_SESSION_LOG_PRE_PRUNE_COMMAND:-}"

project="${CLAUDE_PROJECT_DIR:-$PWD}"
root=""
slog_root_to root "$project"
[[ -n "$root" && -d "$root/sessions" ]] || exit 0

# 1. Sweep pending directories an earlier run handed to an archiver more than
#    24 h ago. One find; nothing to do on most runs.
if [[ -d "$root/prune-pending" ]]; then
  stale=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && stale+=("$d")
  done < <(find "$root/prune-pending" -mindepth 1 -maxdepth 1 -type d -mmin +1440 2>/dev/null)
  ((${#stale[@]})) && rm -rf -- "${stale[@]}" 2>/dev/null
fi

# 2. Recency order (newest first) and the age set, one process each.
shopt -s nullglob
files=("$root/sessions/"*.jsonl)
shopt -u nullglob
((${#files[@]} > keep_n)) || exit 0
declare -A protected=() old=()
i=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  ((i < keep_n)) && protected["$f"]=1
  i=$((i + 1))
done < <(ls -t -- "${files[@]}" 2>/dev/null)
while IFS= read -r f; do
  [[ -n "$f" ]] && old["$f"]=1
done < <(find "$root/sessions" -mindepth 1 -maxdepth 1 -name '*.jsonl' -mmin "+$((keep_days * 1440))" 2>/dev/null)

doomed=()
for f in "${files[@]}"; do
  [[ -n "${protected[$f]:-}" ]] && continue
  [[ -n "${old[$f]:-}" ]] || continue
  doomed+=("$f")
done
((${#doomed[@]})) || exit 0

# 3. Prune: unlink, or move aside for the archiver and detach it.
if [[ -z "$pre_prune" ]]; then
  rm -f -- "${doomed[@]}" 2>/dev/null
  exit 0
fi
pending="$root/prune-pending/${EPOCHSECONDS:-0}-$$"
mkdir -p "$pending" 2>/dev/null || exit 0
mv -- "${doomed[@]}" "$pending/" 2>/dev/null
# Detached: its own session, stdin closed, no inherited fds, so a Windows child
# cannot hold this hook's process tree open past the SessionEnd budget.
(nohup bash -c "$pre_prune"' "$@"' bash "$pending" </dev/null >/dev/null 2>&1 &)
exit 0
