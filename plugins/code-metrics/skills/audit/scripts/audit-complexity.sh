#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
DISPATCH="$PLUGIN_ROOT/scripts/dispatch.sh"
# shellcheck source=../../../scripts/entry-common.sh
source "$PLUGIN_ROOT/scripts/entry-common.sh"

cm_entry_args "${BASH_SOURCE[0]}" 13 "$@"

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
