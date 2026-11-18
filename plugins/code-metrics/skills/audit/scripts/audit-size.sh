#!/usr/bin/env bash
# /code-metrics:audit size entry point: lines per file, comment-aware when
# `scc` resolves, comment-agnostic from the bundled counter otherwise.
#
#   audit-size.sh [--json] [--all] [--base <ref>] [--file-lines <n>] [--commits-since <date>] [--config <resolved.json>] [<path>...]
#
# `--file-lines <n>` replaces the resolved `size.file_lines` reference for this
# run, and the report names the option as the layer that supplied it.
# `--commits-since <date>` adds, for each file at or above the reference, the
# commits since <date> that touched it, automation authors left out.
#
# Prints the markdown report; `--json` prints the `code-metrics/v2` document
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

cm_entry_args "${BASH_SOURCE[0]}" 16 "$@"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=../../../scripts/python-resolve.sh
source "$PLUGIN_ROOT/scripts/python-resolve.sh"
cm_require_python audit-size.sh

cm_split_config "${ARGS[@]}"
if [[ -z "$CM_CONFIG" ]]; then
  CM_CONFIG="$WORK/config.json"
  cm_resolve_config "$CM_CONFIG" || exit 2
fi

FILE_LINES=""
COMMITS_SINCE=""
CHECK=0
REST=()
set -- "${CM_PASS_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--file-lines" ]]; then
    if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
      echo "audit-size.sh: --file-lines takes a positive whole number, got '${2-}'" >&2
      exit 2
    fi
    FILE_LINES="$2"
    shift 2
    continue
  fi
  if [[ "$1" == "--commits-since" ]]; then
    if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
      echo "audit-size.sh: --commits-since takes a date git log --since accepts, got '${2-}'" >&2
      exit 2
    fi
    COMMITS_SINCE="$2"
    shift 2
    continue
  fi
  if [[ "$1" == "--check" ]]; then
    CHECK=1
    shift
    continue
  fi
  REST+=("$1")
  shift
done
CM_PASS_ARGS=("${REST[@]}")
if [[ -n "$FILE_LINES" ]]; then
  "${PY[@]}" -I -c '
import json, sys
source, destination, value = sys.argv[1], sys.argv[2], int(sys.argv[3])
doc = json.load(open(source))
doc.setdefault("size", {})["file_lines"] = value
doc.setdefault("_layers", {})["size.file_lines"] = "this run (--file-lines)"
for entry in doc.get("thresholds", []):
    if entry.get("config_key") == "size.file_lines":
        entry["provenance"] = "passed with --file-lines for this run; the caller states where the number comes from"
json.dump(doc, open(destination, "w"))
' "$CM_CONFIG" "$WORK/config-run.json" "$FILE_LINES" || exit 2
  CM_CONFIG="$WORK/config-run.json"
fi
MODE="$("${PY[@]}" -I -c 'import json,sys; print((json.load(open(sys.argv[1])).get("size") or {}).get("mode") or "file-lines")' "$CM_CONFIG")"
case "$MODE" in
file-lines) MEASURES="file_lines" ;;
iso-8.2.115) MEASURES="file_lines,function_lines" ;;
*)
  echo "audit-size.sh: size.mode must be file-lines or iso-8.2.115, got '$MODE'" >&2
  exit 2
  ;;
esac
RULE="$("${PY[@]}" -I -c 'import json,sys; print((json.load(open(sys.argv[1])).get("size") or {}).get("check") or "report")' "$CM_CONFIG")"
case "$RULE" in
report | crossing | crossing-or-growth) ;;
*)
  echo "audit-size.sh: size.check must be report, crossing or crossing-or-growth, got '$RULE'" >&2
  exit 2
  ;;
esac

bash "$DISPATCH" audit-size --measures "$MEASURES" --config "$CM_CONFIG" "${CM_PASS_ARGS[@]}" >"$WORK/report.json"
rc=$?
[[ $rc -eq 0 || $rc -eq 3 ]] || exit "$rc"
if [[ -n "$COMMITS_SINCE" ]]; then
  "${PY[@]}" -I "$SCRIPT_DIR/size_commits.py" add --since "$COMMITS_SINCE" "$WORK/report.json" || exit 2
fi
if [[ "$CHECK" -eq 1 ]]; then
  "${PY[@]}" -I "$SCRIPT_DIR/size_check.py" add --config "$CM_CONFIG" "$WORK/report.json"
  check_rc=$?
  if [[ $rc -eq 3 && "$RULE" != "report" ]]; then
    echo "audit-size.sh: --check cannot decide: a collector produced nothing parseable (see the run table)" >&2
    rc=2
  elif [[ $rc -ne 3 || $check_rc -ne 0 ]]; then
    rc=$check_rc
  fi
fi
cm_emit_document audit-size "$JSON" "$WORK/report.json" || exit 2
if [[ -n "$COMMITS_SINCE" && "$JSON" -ne 1 ]]; then
  "${PY[@]}" -I "$SCRIPT_DIR/size_commits.py" render "$WORK/report.json"
fi
if [[ "$CHECK" -eq 1 && "$JSON" -ne 1 ]]; then
  "${PY[@]}" -I "$SCRIPT_DIR/size_check.py" render "$WORK/report.json"
fi
exit "$rc"
