#!/usr/bin/env bash
# /code-metrics:audit complexity entry point: cyclomatic and cognitive
# complexity and Halstead difficulty for the files in scope.
#
#   audit-complexity.sh [--json] [--all] [--base <ref>] [--config <resolved.json>] [<path>...]
#
# Prints the markdown report; `--json` prints the `code-metrics/v2` document
# instead. Scope, lanes, and the collector ladder are the dispatcher's
# (scripts/dispatch.sh in the plugin root); this script owns `--json` and the
# measure list it asks for: cyclomatic, cognitive, halstead. Every number is
# printed beside a reference with its provenance and nothing else: no finding,
# no severity, no exit-code gate. Exit codes are the dispatcher's: 0 report
# produced, 2 usage error, 3 a collector ran and produced nothing parseable.
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
