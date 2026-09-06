#!/usr/bin/env bash
# /code-metrics:audit-type-debt entry point: how much of the code is typed,
# per lane, as a percentage from `type-coverage` (TypeScript) and from mypy's
# `--any-exprs-report` (Python).
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
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
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

bash "$DISPATCH" audit-type-debt --measures type_coverage --config "$CONFIG" "${PASS_ARGS[@]}" >"$WORK/report.json"
rc=$?
[[ $rc -eq 0 || $rc -eq 3 ]] || exit "$rc"
if [[ $JSON -eq 1 ]]; then
  cat "$WORK/report.json"
else
  "${PY[@]}" "$REPORT" render <"$WORK/report.json" || exit 2
fi
exit "$rc"
