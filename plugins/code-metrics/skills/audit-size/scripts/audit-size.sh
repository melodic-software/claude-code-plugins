#!/usr/bin/env bash
# /code-metrics:audit-size entry point: lines per file, comment-aware when
# `scc` resolves, comment-agnostic from the bundled counter otherwise.
#
#   audit-size.sh [--json] [--all] [--base <ref>] [--config <resolved.json>] [<path>...]
#
# Prints the markdown report; `--json` prints the `code-metrics/v1` document
# instead. Scope, lanes, and the collector ladder are the dispatcher's
# (scripts/dispatch.sh in the plugin root); this script owns its own options
# and the size mode: `size.mode: file-lines` (default) measures `file_lines`;
# `size.mode: iso-8.2.115` adds `function_lines`, the ISO/IEC 5055 §8.2.115
# form, each function's non-empty lines as a percentage of the file's, from
# a collector that reports function ranges. Exit codes are the dispatcher's:
# 0 report produced, 2 usage error, 3 a collector ran and produced nothing
# parseable.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
DISPATCH="$PLUGIN_ROOT/scripts/dispatch.sh"
REPORT="$PLUGIN_ROOT/scripts/report.py"

JSON=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    JSON=1
    shift
    ;;
  --help | -h)
    sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 0
    ;;
  *)
    ARGS+=("$1")
    shift
    ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=../../../scripts/python-resolve.sh
source "$PLUGIN_ROOT/scripts/python-resolve.sh"
if ! cm_resolve_python; then
  echo "audit-size.sh: Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite" >&2
  exit 2
fi

# Resolve the configuration once (or take the caller's --config), so the
# size mode is read from the same document the dispatcher measures against.
CONFIG=""
PASS_ARGS=()
i=0
while [[ $i -lt ${#ARGS[@]} ]]; do
  if [[ "${ARGS[$i]}" == "--config" && $((i + 1)) -lt ${#ARGS[@]} ]]; then
    CONFIG="${ARGS[$((i + 1))]}"
    i=$((i + 2))
    continue
  fi
  PASS_ARGS+=("${ARGS[$i]}")
  i=$((i + 1))
done
if [[ -z "$CONFIG" ]]; then
  CONFIG="$WORK/config.json"
  "${PY[@]}" "$PLUGIN_ROOT/scripts/resolve-config.py" --ladder "$PLUGIN_ROOT/scripts/collector-ladder.tsv" \
    --home "${CODE_METRICS_HOME:-${HOME:-/}}" >"$CONFIG" || exit 2
fi
MODE="$("${PY[@]}" -c 'import json,sys; print((json.load(open(sys.argv[1])).get("size") or {}).get("mode") or "file-lines")' "$CONFIG")"
case "$MODE" in
file-lines) MEASURES="file_lines" ;;
iso-8.2.115) MEASURES="file_lines,function_lines" ;;
*)
  echo "audit-size.sh: size.mode must be file-lines or iso-8.2.115, got '$MODE'" >&2
  exit 2
  ;;
esac

bash "$DISPATCH" audit-size --measures "$MEASURES" --config "$CONFIG" "${PASS_ARGS[@]}" >"$WORK/report.json"
rc=$?
[[ $rc -eq 0 || $rc -eq 3 ]] || exit "$rc"
if [[ $JSON -eq 1 ]]; then
  cat "$WORK/report.json"
else
  "${PY[@]}" "$REPORT" render <"$WORK/report.json" || exit 2
fi
exit "$rc"
