#!/usr/bin/env bash
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

if [[ -d "$root/prune-pending" ]]; then
  stale=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && stale+=("$d")
  done < <(find "$root/prune-pending" -mindepth 1 -maxdepth 1 -type d -mmin +1440 2>/dev/null)
  ((${#stale[@]})) && rm -rf -- "${stale[@]}" 2>/dev/null
fi

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
  [[ -z "${protected[$f]:-}" && -n "${old[$f]:-}" ]] && doomed+=("$f")
done
((${#doomed[@]})) || exit 0

if [[ -z "$pre_prune" ]]; then
  rm -f -- "${doomed[@]}" 2>/dev/null
  exit 0
fi
pending="$root/prune-pending/${EPOCHSECONDS:-0}-$$"
mkdir -p "$pending" 2>/dev/null || exit 0
mv -- "${doomed[@]}" "$pending/" 2>/dev/null
(nohup bash -c "$pre_prune"' "$@"' bash "$pending" </dev/null >/dev/null 2>&1 &)
exit 0
