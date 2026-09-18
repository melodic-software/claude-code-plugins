# shellcheck shell=bash
# Sourced by the dispatcher and by every audit entry point: the four pieces
# each of them would otherwise repeat verbatim.
#
#   cm_usage_banner <file> <last line>    print <file>'s leading comment block,
#                                         lines 2..<last line>, with the comment
#                                         marker stripped, on stderr
#   cm_split_config <argument>...         split `--config <path>` out of the
#                                         arguments into CM_CONFIG and leave the
#                                         rest, in order, in CM_PASS_ARGS
#   cm_resolve_config <destination> [<ladder>]
#                                         resolve the configuration cascade into
#                                         <destination>; return the resolver's
#                                         own status
#   cm_emit_document <skill> <json flag> <document> [<render argument>...]
#                                         print <document> when the flag is 1,
#                                         else persist it and render the markdown
#
# The banner's last line is the caller's own rather than the end of its comment
# block: each script's `--help` output is its published contract, and several of
# them stop short of that end.
#
# The caller supplies `PY` (from python-resolve.sh) for the two functions that
# run the interpreter.
# shellcheck disable=SC2154

CM_ENTRY_LIB_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

cm_usage_banner() {
  # One sed rather than a range print piped into a strip: the `-e` fragments
  # give the braces the newlines a BSD sed wants around them.
  sed -n -e "2,${2}{" -e 's/^# \{0,1\}//' -e p -e '}' "$1" >&2
}

# CM_CONFIG and CM_PASS_ARGS are consumed by the sourcing script, not here.
# shellcheck disable=SC2034
cm_split_config() {
  CM_CONFIG=""
  CM_PASS_ARGS=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--config" && $# -gt 1 ]]; then
      CM_CONFIG="$2"
      shift 2
      continue
    fi
    CM_PASS_ARGS+=("$1")
    shift
  done
}

cm_resolve_config() {
  "${PY[@]}" "$CM_ENTRY_LIB_DIR/resolve-config.py" \
    --ladder "${2:-$CM_ENTRY_LIB_DIR/collector-ladder.tsv}" \
    --home "${CODE_METRICS_HOME:-${HOME:-/}}" >"$1"
}

cm_emit_document() {
  local skill="$1" json="$2" document="$3" persisted
  shift 3
  if [[ "$json" -eq 1 ]]; then
    cat "$document"
    return 0
  fi
  local render_args=("$@")
  # shellcheck source=persist-report.sh
  source "$CM_ENTRY_LIB_DIR/persist-report.sh"
  # A report directory that cannot be written leaves the renderer without a
  # path, and the cap line then says to re-run with --json instead.
  if persisted="$(cm_persist_report "$skill" "$document")"; then
    render_args+=(--document "$persisted")
  fi
  "${PY[@]}" "$CM_ENTRY_LIB_DIR/report.py" render "${render_args[@]}" <"$document"
}
