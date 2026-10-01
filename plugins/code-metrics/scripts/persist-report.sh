# shellcheck shell=bash
# Sourced by every audit entry point: keep the `code-metrics/v2` document the
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
# scratch directory), else <root>/<state-key>, where <root> is
# <CLAUDE_PLUGIN_DATA>/reports, else ~/.claude/plugins/data/code-metrics/reports
# (the Bash tool does not export CLAUDE_PLUGIN_DATA), and <state-key> is what
# lib/state-key.sh prints for the working directory. One project's runs share a
# directory, so the newest-CM_REPORTS_KEPT retention counts per project. When
# the key cannot be derived the function says why on stderr and returns 1
# rather than fall back to a directory shared by every project. A directory
# that cannot be written is reported the same way; the caller then renders
# without a path, and the cap line says to re-run with --json instead.
# Loose <skill>-*.json files directly under <root> are named once on stderr
# and never read, moved or pruned.

CM_REPORTS_KEPT="${CM_REPORTS_KEPT:-20}"
CM_PERSIST_SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

cm_report_root() {
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
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
