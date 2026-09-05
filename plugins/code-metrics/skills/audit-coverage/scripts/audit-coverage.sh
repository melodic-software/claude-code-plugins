#!/usr/bin/env bash
# /code-metrics:audit-coverage entry point: line coverage per file and per
# function, and CRAP per function, read from coverage artifacts a build
# already produced. It never runs a test command.
#
#   audit-coverage.sh [--json] [--all] [--base <ref>] [--config <resolved.json>] [--artifacts <path>]... [<path>...]
#
# Prints the markdown report; `--json` prints the `code-metrics/v1` document
# instead. Artifacts come from every `--artifacts` and from
# `coverage.artifacts` in the config; with none named, well-known names are
# looked for under the repository root, at most two directory levels deep.
# Complexity for the CRAP formula comes from the sibling audit-complexity
# skill's entry script, run over the same scope. Exit codes: 0 report
# produced, including an empty one; 2 usage error, which includes a named
# artifact or scope path that does not exist; 3 a collector ran and produced
# nothing parseable.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
REPORT="$PLUGIN_ROOT/scripts/report.py"
PARSERS="$PLUGIN_ROOT/scripts/parsers"
COMPLEXITY="$PLUGIN_ROOT/skills/audit-complexity/scripts/audit-complexity.sh"
# Well-known artifact names, in the order they are looked for. Directories
# excluded from the walk: node_modules, .git, vendor.
WELL_KNOWN=(coverage/lcov.info lcov.info coverage.xml cobertura.xml coverage.json coverage.out cover.out)

JSON=0
CONFIG=""
NAMED=()
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    JSON=1
    shift
    ;;
  --artifacts)
    if [[ $# -lt 2 ]]; then
      echo "audit-coverage.sh: --artifacts needs a path" >&2
      exit 2
    fi
    NAMED+=("$2")
    shift 2
    ;;
  --config)
    if [[ $# -lt 2 ]]; then
      echo "audit-coverage.sh: --config needs a path" >&2
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
  echo "audit-coverage.sh: Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite" >&2
  exit 2
fi

if [[ -z "$CONFIG" ]]; then
  CONFIG="$WORK/config.json"
  "${PY[@]}" "$PLUGIN_ROOT/scripts/resolve-config.py" --ladder "$PLUGIN_ROOT/scripts/collector-ladder.tsv" \
    --home "${CODE_METRICS_HOME:-${HOME:-/}}" >"$CONFIG" || exit 2
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$ROOT" ]] || ROOT="$PWD"

# `coverage.artifacts` and `coverage.path_prefix_strip` from the resolved
# config, one entry per line.
config_list() {
  "${PY[@]}" -c '
import json, sys
document = json.load(open(sys.argv[1]))
node = document.get("coverage") or {}
for entry in node.get(sys.argv[2]) or []:
    print(entry)
' "$CONFIG" "$1"
}

while IFS= read -r line; do
  [[ -n "$line" ]] && NAMED+=("$line")
done < <(config_list artifacts)

PREFIX_ARGS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && PREFIX_ARGS+=(--prefix-strip "$line")
done < <(config_list path_prefix_strip)

# An explicitly named artifact that does not exist is a usage error, so a
# stale path never degrades silently into "no coverage".
ARTIFACT_PATHS=()
SEARCHED=()
for named in ${NAMED[@]+"${NAMED[@]}"}; do
  candidate="$named"
  [[ "$candidate" == /* || -e "$candidate" ]] || candidate="$ROOT/$named"
  if [[ ! -f "$candidate" ]]; then
    echo "audit-coverage.sh: named coverage artifact does not exist: $named" >&2
    exit 2
  fi
  ARTIFACT_PATHS+=("$candidate")
  SEARCHED+=("$named")
done

if [[ ${#ARTIFACT_PATHS[@]} -eq 0 ]]; then
  for name in "${WELL_KNOWN[@]}"; do
    SEARCHED+=("$name")
    while IFS= read -r found; do
      [[ -n "$found" ]] && ARTIFACT_PATHS+=("$found")
    done < <(find "$ROOT" -maxdepth 3 \
      \( -name node_modules -o -name .git -o -name vendor \) -prune -o \
      -type f -path "*/$name" -print 2>/dev/null)
  done
fi

# Format detection by content, never by extension: lcov section headers, a
# Cobertura root element, a coverage.py JSON report, a Go cover profile.
detect_format() {
  local artifact="$1" first
  first="$(grep -v '^[[:space:]]*$' "$artifact" 2>/dev/null | head -n 1)"
  case "$first" in
  mode:*)
    printf 'go_cover\n'
    return 0
    ;;
  *) ;;
  esac
  if head -n 200 "$artifact" | grep -q '^SF:' || head -n 200 "$artifact" | grep -q '^TN:'; then
    printf 'lcov\n'
    return 0
  fi
  if head -n 200 "$artifact" | grep -q '<coverage'; then
    printf 'cobertura\n'
    return 0
  fi
  if head -c 4096 "$artifact" | grep -q '"files"' && head -c 4096 "$artifact" | grep -q '"meta"'; then
    printf 'coverage_py_json\n'
    return 0
  fi
  return 1
}

ARTIFACT_ARGS=()
index=0
for artifact in ${ARTIFACT_PATHS[@]+"${ARTIFACT_PATHS[@]}"}; do
  format="$(detect_format "$artifact")"
  if [[ -z "$format" ]]; then
    echo "audit-coverage.sh: unrecognized coverage format, skipped: $artifact" >&2
    continue
  fi
  parsed="$WORK/parsed-$index.json"
  if ! "${PY[@]}" "$PARSERS/$format.py" "$artifact" >"$parsed"; then
    echo "audit-coverage.sh: $format parser produced nothing for $artifact, skipped" >&2
    continue
  fi
  ARTIFACT_ARGS+=(--artifacts "$format:$parsed")
  index=$((index + 1))
done

SEARCHED_ARGS=()
for entry in ${SEARCHED[@]+"${SEARCHED[@]}"}; do
  SEARCHED_ARGS+=(--searched "$entry")
done

bash "$COMPLEXITY" --json --config "$CONFIG" ${ARGS[@]+"${ARGS[@]}"} >"$WORK/complexity.json"
rc=$?
if [[ $rc -ne 0 && $rc -ne 3 ]]; then
  exit "$rc"
fi

# The scope block travels with the report. The file list the join keys on is
# the dispatcher's own resolved scope (same arguments, same exclusions), not
# the files a complexity collector happened to emit rows for: a file with no
# functions, or a lane whose collector is absent, still gets its file-level
# coverage; complexity is needed only for CRAP.
"${PY[@]}" -c '
import json, sys
document = json.load(open(sys.argv[1]))
json.dump(document.get("scope") or {}, open(sys.argv[2], "w"))
' "$WORK/complexity.json" "$WORK/scope.json" || exit 2
bash "$PLUGIN_ROOT/scripts/dispatch.sh" audit-coverage --measures coverage --config "$CONFIG" \
  --print-scope ${ARGS[@]+"${ARGS[@]}"} >"$WORK/scope-files.txt" || exit 2

"${PY[@]}" "$SCRIPT_DIR/join.py" --complexity "$WORK/complexity.json" \
  --scope "$WORK/scope-files.txt" --root "$ROOT" \
  ${PREFIX_ARGS[@]+"${PREFIX_ARGS[@]}"} ${ARTIFACT_ARGS[@]+"${ARTIFACT_ARGS[@]}"} \
  ${SEARCHED_ARGS[@]+"${SEARCHED_ARGS[@]}"} \
  --measures-out "$WORK/rows.jsonl" --run-out "$WORK/run.jsonl" >/dev/null || exit 2

"${PY[@]}" "$REPORT" thresholds --config "$CONFIG" --measures coverage,crap >"$WORK/thresholds.json" || exit 2
"${PY[@]}" "$REPORT" assemble --skill audit-coverage --scope "$WORK/scope.json" \
  --run "$WORK/run.jsonl" --measures "$WORK/rows.jsonl" \
  --thresholds "$WORK/thresholds.json" >"$WORK/report.json" || exit 2

if [[ $JSON -eq 1 ]]; then
  cat "$WORK/report.json"
else
  "${PY[@]}" "$REPORT" render <"$WORK/report.json" || exit 2
fi
exit "$rc"
