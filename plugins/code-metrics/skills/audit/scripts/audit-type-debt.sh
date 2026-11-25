#!/usr/bin/env bash
set -uo pipefail

USAGE="$(
  cat <<'EOF'
/code-metrics:audit type-debt entry point: how much of the code is typed, per file and per lane.
  audit-type-debt.sh [--json] [--all] [--base <ref>] [--config <resolved.json>] [<path>...]
  --json                    print the code-metrics/v2 document instead of the report
  --all                     measure every file, not the change
  --base <ref>              measure the change from the merge-base with <ref>
  --config <resolved.json>  a resolved configuration
Exit: 0 report produced (including a run that measured nothing); 2 usage error;
3 a collector ran and produced nothing parseable.
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
cm_require_python audit-type-debt.sh

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
