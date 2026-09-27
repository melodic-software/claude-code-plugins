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
# shellcheck source=../../../scripts/entry-common.sh
source "$PLUGIN_ROOT/scripts/entry-common.sh"

JSON=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    JSON=1
    shift
    ;;
  --help | -h)
    cm_usage_banner "${BASH_SOURCE[0]}" 11
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
cm_split_config "${ARGS[@]}"
if [[ -z "$CM_CONFIG" ]]; then
  CM_CONFIG="$WORK/config.json"
  cm_resolve_config "$CM_CONFIG" || exit 2
fi
MODE="$("${PY[@]}" -c 'import json,sys; print((json.load(open(sys.argv[1])).get("size") or {}).get("mode") or "file-lines")' "$CM_CONFIG")"
case "$MODE" in
file-lines) MEASURES="file_lines" ;;
iso-8.2.115) MEASURES="file_lines,function_lines" ;;
*)
  echo "audit-size.sh: size.mode must be file-lines or iso-8.2.115, got '$MODE'" >&2
  exit 2
  ;;
esac

bash "$DISPATCH" audit-size --measures "$MEASURES" --config "$CM_CONFIG" "${CM_PASS_ARGS[@]}" >"$WORK/report.json"
rc=$?
[[ $rc -eq 0 || $rc -eq 3 ]] || exit "$rc"
cm_emit_document audit-size "$JSON" "$WORK/report.json" || exit 2
exit "$rc"
