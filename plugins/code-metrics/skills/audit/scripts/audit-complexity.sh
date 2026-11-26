#!/usr/bin/env bash
set -uo pipefail

USAGE="$(
  cat <<'EOF'
/code-metrics:audit complexity entry point: cyclomatic and cognitive complexity and Halstead
difficulty for the files in scope.
  audit-complexity.sh [--json] [--all] [--base <ref>] [--config <resolved.json>] [<path>...]
  --json                    print the code-metrics/v2 document instead of the report
  --all                     measure every file, not the change
  --base <ref>              measure the change from the merge-base with <ref>
  --config <resolved.json>  a resolved configuration
Exit: 0 report produced; 2 usage error; 3 a collector ran and produced nothing parseable.
EOF
)"

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
DISPATCH="$PLUGIN_ROOT/scripts/dispatch.sh"
# shellcheck source=../../../scripts/entry-common.sh
source "$PLUGIN_ROOT/scripts/entry-common.sh"

cm_entry_args --usage "$USAGE" "$@"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=../../../scripts/python-resolve.sh
source "$PLUGIN_ROOT/scripts/python-resolve.sh"
cm_require_python audit-complexity.sh

bash "$DISPATCH" audit-complexity --measures cyclomatic,cognitive,halstead "${ARGS[@]}" >"$WORK/report.json"
rc=$?
[[ $rc -eq 0 || $rc -eq 3 ]] || exit "$rc"
cm_emit_document audit-complexity "$JSON" "$WORK/report.json" || exit 2
exit "$rc"
