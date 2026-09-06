#!/usr/bin/env bash
# /code-metrics:audit-duplication entry point: clone groups across the scope,
# minus the replication the target repository declares about itself.
#
#   audit-duplication.sh [--json] [--all] [--base <ref>] [--config <resolved.json>]
#                        [--registry <file>]... [<path>...]
#
# Prints the markdown report; `--json` prints the `code-metrics/v1` document
# instead. Scope, lanes, and the collector ladder are the dispatcher's
# (scripts/dispatch.sh in the plugin root); this script owns `--registry` and
# the duplication tunables it exports for the collector adapters
# (CODE_METRICS_DUP_MIN_TOKENS, CODE_METRICS_DUP_MIN_LINES,
# CODE_METRICS_DUP_IGNORE, from `duplication.*` in the resolved config).
# Registries come from every `--registry` plus `duplication.registries`, each
# resolved against the repository root; a named registry that does not exist is
# a usage error. Exit codes are the dispatcher's: 0 report produced, 2 usage
# error, 3 a collector ran and produced nothing parseable.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
DISPATCH="$PLUGIN_ROOT/scripts/dispatch.sh"
REPORT="$PLUGIN_ROOT/scripts/report.py"
FILTER="$SCRIPT_DIR/registry-filter.py"

JSON=0
CONFIG=""
REGISTRY_ARGS=()
PASS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    JSON=1
    shift
    ;;
  --registry)
    if [[ $# -lt 2 ]]; then
      echo "audit-duplication.sh: --registry needs a value" >&2
      exit 2
    fi
    REGISTRY_ARGS+=("$2")
    shift 2
    ;;
  --config)
    if [[ $# -lt 2 ]]; then
      echo "audit-duplication.sh: --config needs a value" >&2
      exit 2
    fi
    CONFIG="$2"
    shift 2
    ;;
  --help | -h)
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 0
    ;;
  *)
    PASS_ARGS+=("$1")
    shift
    ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=../../../scripts/python-resolve.sh
source "$PLUGIN_ROOT/scripts/python-resolve.sh"
if ! cm_resolve_python; then
  echo "audit-duplication.sh: Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || ROOT="$PWD"

# Resolve the configuration once (or take the caller's --config), so the
# tunables the adapters read and the registries this script applies come from
# the same document the dispatcher measures against.
if [[ -z "$CONFIG" ]]; then
  CONFIG="$WORK/config.json"
  "${PY[@]}" "$PLUGIN_ROOT/scripts/resolve-config.py" --ladder "$PLUGIN_ROOT/scripts/collector-ladder.tsv" \
    --home "${CODE_METRICS_HOME:-${HOME:-/}}" >"$CONFIG" || exit 2
fi

# Three tunables and then one line per configured registry, in that order.
mapfile -t DUP < <("${PY[@]}" -c '
import json, sys

section = json.load(open(sys.argv[1])).get("duplication") or {}


def number(key, fallback):
    value = section.get(key)
    return value if isinstance(value, int) and not isinstance(value, bool) else fallback


print(number("min_tokens", 50))
print(number("min_lines", 5))
ignore = section.get("ignore")
print(",".join(str(item) for item in ignore) if isinstance(ignore, list) else "")
for registry in section.get("registries") or []:
    print(str(registry))
' "$CONFIG")
if [[ ${#DUP[@]} -lt 3 ]]; then
  echo "audit-duplication.sh: the resolved configuration could not be read" >&2
  exit 2
fi
export CODE_METRICS_DUP_MIN_TOKENS="${DUP[0]}"
export CODE_METRICS_DUP_MIN_LINES="${DUP[1]}"
export CODE_METRICS_DUP_IGNORE="${DUP[2]}"

FILTER_ARGS=(--root "$ROOT")
resolve_registry() {
  # A registry path as given, else the same path under the repository root.
  if [[ -f "$1" ]]; then
    printf '%s\n' "$1"
  elif [[ -f "$ROOT/$1" ]]; then
    printf '%s\n' "$ROOT/$1"
  else
    return 1
  fi
}
for registry in "${REGISTRY_ARGS[@]:-}" "${DUP[@]:3}"; do
  [[ -n "$registry" ]] || continue
  if ! resolved="$(resolve_registry "$registry")"; then
    echo "audit-duplication.sh: registry not found: $registry" >&2
    exit 2
  fi
  FILTER_ARGS+=(--registry "$resolved")
done

bash "$DISPATCH" audit-duplication --measures duplication --config "$CONFIG" ${PASS_ARGS[@]+"${PASS_ARGS[@]}"} >"$WORK/report.json"
rc=$?
[[ $rc -eq 0 || $rc -eq 3 ]] || exit "$rc"

# Exclude the declared replication, recompute the totals from what survived,
# then state the zero the recomputation drops when every group was excluded.
"${PY[@]}" "$FILTER" "${FILTER_ARGS[@]}" <"$WORK/report.json" >"$WORK/filtered.json" || exit 2
"${PY[@]}" "$REPORT" resummarize <"$WORK/filtered.json" >"$WORK/summed.json" || exit 2
"${PY[@]}" "$FILTER" --zero-floor --root "$ROOT" <"$WORK/summed.json" >"$WORK/final.json" || exit 2

if [[ $JSON -eq 1 ]]; then
  cat "$WORK/final.json"
else
  "${PY[@]}" "$REPORT" render <"$WORK/final.json" || exit 2
fi
exit "$rc"
