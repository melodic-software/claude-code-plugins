# shellcheck shell=bash

# shellcheck disable=SC2154  # OTEL_PROG is set by the sourcing script.
die() {
  printf '%s: %s\n' "$OTEL_PROG" "$1" >&2
  exit 2
}

sql_path() { # native duckdb.exe cannot read MSYS paths; double quotes for a SQL literal
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then p="$(cygpath -m "$p")"; fi
  printf '%s\n' "${p//\'/\'\'}"
}

otel_store_to() {
  printf -v "$1" '%s' "${CC_OTEL_STORE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/observability/otel}"
}
