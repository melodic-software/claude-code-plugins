# shellcheck shell=bash
# PY is set by cm_require_python through python-resolve.sh, which the caller sources.
# shellcheck disable=SC2154

CM_ENTRY_LIB_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

cm_usage_banner() {
  if [[ "$1" == --usage ]]; then
    printf '%s\n' "$2" >&2
    return
  fi
  sed -n -e "2,${2}{" -e 's/^# \{0,1\}//' -e p -e '}' "$1" >&2
}

# JSON and ARGS are consumed by the sourcing script, not here.
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
    --user-file)
      cm_set_user_file "$@" || exit 2
      shift 2
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

cm_set_user_file() {
  if [[ $# -lt 2 ]]; then
    echo "$1 needs a value: the config_file option's value" >&2
    return 2
  fi
  export CODE_METRICS_USER_FILE="$2"
}

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
    --home "${CODE_METRICS_HOME:-${HOME:-/}}" \
    --user-file "${CODE_METRICS_USER_FILE:-}" >"$1"
}

cm_anchor_document() {
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
  if persisted="$(cm_persist_report "$skill" "$document")"; then
    render_args+=(--document "$persisted")
  fi
  "${PY[@]}" "$CM_ENTRY_LIB_DIR/report.py" render "${render_args[@]}" <"$document"
}
