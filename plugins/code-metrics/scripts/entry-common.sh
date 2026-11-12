# shellcheck shell=bash
# Sourced by the dispatcher and by every audit entry point: the seven pieces
# each of them would otherwise repeat verbatim.
#
#   cm_usage_banner <file> <last line>    print <file>'s leading comment block,
#                                         lines 2..<last line>, with the comment
#                                         marker stripped, on stderr
#   cm_entry_args <file> <last line> <argument>...
#                                         parse the `--json`, `--help` and pass-
#                                         through options into JSON and ARGS; on
#                                         `--help` print the banner and exit 0
#   cm_require_python <script name>       resolve the interpreter into PY, or
#                                         print the prerequisite message and
#                                         exit 2
#   cm_split_config <argument>...         split `--config <path>` out of the
#                                         arguments into CM_CONFIG and leave the
#                                         rest, in order, in CM_PASS_ARGS
#   cm_resolve_config <destination> [<ladder>]
#                                         resolve the configuration cascade into
#                                         <destination>; return the resolver's
#                                         own status
#   cm_anchor_document <document>        record the report's root and make its
#                                         measured paths relative to it, in
#                                         place; a document already anchored is
#                                         left unchanged
#   cm_emit_document <skill> <json flag> <document> [<render argument>...]
#                                         print <document> when the flag is 1,
#                                         else persist it and render the markdown
#
# The banner's last line is the caller's own rather than the end of its comment
# block: each script's `--help` output is its published contract, and several of
# them stop short of that end.
#
# The functions that run the interpreter read `PY`, which cm_require_python
# sets through python-resolve.sh, a file the caller sources.
# shellcheck disable=SC2154

CM_ENTRY_LIB_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

cm_usage_banner() {
  # One sed rather than a range print piped into a strip: the `-e` fragments
  # give the braces the newlines a BSD sed wants around them.
  sed -n -e "2,${2}{" -e 's/^# \{0,1\}//' -e p -e '}' "$1" >&2
}

# JSON and ARGS are consumed by the sourcing script, not here. The caller
# passes its own path: inside this function BASH_SOURCE[0] is this file.
# shellcheck disable=SC2034
cm_entry_args() {
  local file="$1" last="$2"
  shift 2
  JSON=0
  ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      JSON=1
      shift
      ;;
    --help | -h)
      cm_usage_banner "$file" "$last"
      exit 0
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
    esac
  done
}

# The caller sources python-resolve.sh, which defines cm_resolve_python.
cm_require_python() {
  if ! cm_resolve_python; then
    echo "$1: Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite" >&2
    exit 2
  fi
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

cm_anchor_document() {
  # The root is the repository's top level, else the working directory. `-W`
  # (Git Bash) gives the Windows path the interpreter reports; elsewhere `-P`
  # gives the physical path, the one `git` and the interpreter's own working
  # directory report, so the two compare.
  local document="$1" kind="directory" root top anchored
  root="$(pwd -W 2>/dev/null || pwd -P)"
  if top="$(git rev-parse --show-toplevel 2>/dev/null)" && top="${top%$'\r'}" && [[ -n "$top" ]]; then
    kind="repository"
    root="$top"
  fi
  anchored="$(mktemp)"
  if ! "${PY[@]}" "$CM_ENTRY_LIB_DIR/report.py" anchor --root "$root" --kind "$kind" <"$document" >"$anchored"; then
    rm -f "$anchored"
    return 2
  fi
  mv "$anchored" "$document"
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
