#!/usr/bin/env bash
# /code-metrics:audit-type-debt entry point: how much of the code is typed,
# per file and per lane, as a percentage from `type-coverage` (TypeScript) and
# from mypy's `--any-exprs-report` (Python).
#
#   audit-type-debt.sh [--json] [--all] [--base <ref>] [--config <resolved.json>] [<path>...]
#
# Prints the markdown report; `--json` prints the `code-metrics/v1` document
# instead. Scope, lanes, and the collector ladder are the dispatcher's
# (scripts/dispatch.sh in the plugin root); this script owns its own options.
# Bash, Go, and C# report `not-applicable`: no tool produces a comparable
# percentage for them. Exit codes are the dispatcher's: 0 report produced
# (including a run that measured nothing), 2 usage error, 3 a collector ran
# and produced nothing parseable.
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
    cm_usage_banner "${BASH_SOURCE[0]}" 14
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
  echo "audit-type-debt.sh: Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite" >&2
  exit 2
fi

# Resolve the configuration once (or take the caller's --config), so the
# reference the report prints is read from the same document the dispatcher
# measured against.
cm_split_config "${ARGS[@]}"
if [[ -z "$CM_CONFIG" ]]; then
  CM_CONFIG="$WORK/config.json"
  cm_resolve_config "$CM_CONFIG" || exit 2
fi

bash "$DISPATCH" audit-type-debt --measures type_coverage --config "$CM_CONFIG" "${CM_PASS_ARGS[@]}" >"$WORK/report.json"
rc=$?
[[ $rc -eq 0 || $rc -eq 3 ]] || exit "$rc"
cm_emit_document audit-type-debt "$JSON" "$WORK/report.json" || exit 2
exit "$rc"
