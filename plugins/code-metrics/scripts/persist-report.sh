# shellcheck shell=bash

CM_REPORTS_KEPT="${CM_REPORTS_KEPT:-20}"
CM_PERSIST_SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

cm_report_root() {
  local seg="${CLAUDE_PLUGIN_DATA:-}"
  seg="${seg%[/\\]}"
  seg="${seg##*[/\\]}"
  if [[ "$seg" == code-metrics || "$seg" == code-metrics-* ]]; then
    printf '%s/reports\n' "$CLAUDE_PLUGIN_DATA"
  else
    printf '%s/.claude/plugins/data/code-metrics/reports\n' "${HOME:-.}"
  fi
}

cm_report_dir() {
  if [[ -n "${CODE_METRICS_REPORT_DIR:-}" ]]; then
    printf '%s\n' "$CODE_METRICS_REPORT_DIR"
    return 0
  fi
  local key
  if ! key="$(bash "$CM_PERSIST_SCRIPT_DIR/../lib/state-key.sh")" || [[ -z "$key" ]]; then
    printf 'code-metrics: cannot derive the per-project state key from %s; no report is kept\n' \
      "$PWD" >&2
    return 1
  fi
  printf '%s/%s\n' "$(cm_report_root)" "${key%$'\r'}"
}

cm_note_leftovers() {
  [[ -n "${CODE_METRICS_REPORT_DIR:-}" || -n "${CM_LEFTOVERS_NOTED:-}" ]] && return 0
  local root
  root="$(cm_report_root)"
  compgen -G "$root/$1-*.json" >/dev/null || return 0
  CM_LEFTOVERS_NOTED=1
  printf 'code-metrics: %s holds report files kept without a project key; nothing reads or prunes them, and they may be deleted\n' \
    "$root" >&2
}

cm_persist_report() {
  local skill="$1" source="$2" dir stamp target suffix=0
  dir="$(cm_report_dir)" || return 1
  cm_note_leftovers "$skill"
  if ! mkdir -p "$dir" 2>/dev/null || [[ ! -w "$dir" ]]; then
    printf '%s: the report directory %s is not writable; the full document is available with --json\n' \
      "$skill" "$dir" >&2
    return 1
  fi
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  target="$dir/$skill-$stamp.json"
  while [[ -e "$target" ]]; do
    suffix=$((suffix + 1))
    target="$dir/$skill-$stamp-$suffix.json"
  done
  cp "$source" "$target" || return 1
  local kept=("$dir/$skill"-*.json)
  local excess=$((${#kept[@]} - CM_REPORTS_KEPT))
  local i
  for ((i = 0; i < excess; i++)); do
    rm -f "${kept[i]}"
  done
  printf '%s\n' "$target"
}
