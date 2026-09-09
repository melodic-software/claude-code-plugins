# shellcheck shell=bash
# Sourced by every audit entry point: keep the `code-metrics/v1` document the
# markdown was rendered from, so the table's cap line and its summary can
# name a file that exists instead of a document a temporary directory
# deleted on exit.
#
#   cm_report_dir                       print the directory documents are kept in
#   cm_persist_report <skill> <json>    copy <json> there as <skill>-<UTC stamp>.json,
#                                       print the path, keep the newest
#                                       CM_REPORTS_KEPT per skill
#
# The directory is CODE_METRICS_REPORT_DIR when set (the suites point it at a
# scratch directory), else <CLAUDE_PLUGIN_DATA>/reports, else
# ~/.claude/plugins/data/code-metrics/reports, because the Bash tool does not
# export CLAUDE_PLUGIN_DATA and the plugin's data directory is where a run's
# artifacts belong. A directory that cannot be written is reported on stderr
# and the function returns 1; the caller then renders without a path, and
# the cap line says to re-run with --json instead.

CM_REPORTS_KEPT="${CM_REPORTS_KEPT:-20}"

cm_report_dir() {
  if [[ -n "${CODE_METRICS_REPORT_DIR:-}" ]]; then
    printf '%s\n' "$CODE_METRICS_REPORT_DIR"
  elif [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    printf '%s/reports\n' "$CLAUDE_PLUGIN_DATA"
  else
    printf '%s/.claude/plugins/data/code-metrics/reports\n' "${HOME:-.}"
  fi
}

cm_persist_report() {
  local skill="$1" source="$2" dir stamp target suffix=0
  dir="$(cm_report_dir)"
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
  # The stamp sorts the same way it was written, so the glob's order is the
  # documents' age and everything but the newest CM_REPORTS_KEPT can go.
  local kept=("$dir/$skill"-*.json)
  local excess=$((${#kept[@]} - CM_REPORTS_KEPT))
  local i
  for ((i = 0; i < excess; i++)); do
    rm -f "${kept[i]}"
  done
  printf '%s\n' "$target"
}
