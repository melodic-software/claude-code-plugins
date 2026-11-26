#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
# shellcheck source=lib/python-probe.sh
. "$SCRIPT_DIR/lib/python-probe.sh" || exit 1
cd "${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}" || exit 1
foreign=0
[[ "$(pwd -P)" == "$(cd "$SCRIPT_DIR/.." && pwd -P)" ]] || foreign=1

runs_checked_code() {
  ((foreign)) || return 0
  echo "SKIP $1 (runs code from the checked tree)"
  return 1
}

usage() {
  echo "usage: validate-plugins.sh [--only \"<plugin> ...\"]" >&2
  exit 2
}

limited=0
only=()
case "${1:-}" in
'') ;;
--only)
  [[ $# -eq 2 ]] || usage
  limited=1
  for name in $2; do
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ || ! -d "plugins/$name" ]]; then
      echo "error: '$name' is not a plugin under plugins/" >&2
      exit 2
    fi
    only+=("plugins/$name/")
  done
  ;;
*) usage ;;
esac

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not on PATH" >&2
  exit 2
fi
if ((foreign)) && [[ -n "${CHECK_SKIP_CONTRACTS-}" ]]; then
  echo "SKIP contract-validator ($CHECK_SKIP_CONTRACTS)"
else
  contracts=$(node "$SCRIPT_DIR/validate-plugin-contracts.mjs" 2>&1) || {
    printf '%s\n' "$contracts"
    exit 1
  }
  printf '%s\n' "$contracts"
  if grep -q '^warning: ' <<<"$contracts"; then
    echo "error: the plugin contract validator printed a warning; the tree must draw none" >&2
    exit 1
  fi
fi
bash "$SCRIPT_DIR/check-publisher-token-alignment.sh" || exit 1
node "$SCRIPT_DIR/generate-marketplace.mjs" --check || exit 1
node "$SCRIPT_DIR/generate-catalog.mjs" --check || exit 1
if { cmp -s "$SCRIPT_DIR/cheatsheet-config.mjs" scripts/cheatsheet-config.mjs &&
  cmp -s "$SCRIPT_DIR/generate-cheatsheet.mjs" scripts/generate-cheatsheet.mjs; } ||
  runs_checked_code "cheatsheet drift"; then
  node "$SCRIPT_DIR/generate-cheatsheet.mjs" --check --root . || exit 1
fi
if runs_checked_code "identity-prerequisites drift"; then
  node plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs --check || exit 1
fi

if runs_checked_code "native-overlap registry"; then
  OVERLAP="plugins/harness-ops/skills/audit-native-overlap/scripts/overlap.py"
  OVERLAP_FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$OVERLAP")"
  if [[ -z "$OVERLAP_FLOOR" ]]; then
    echo "error: could not parse MIN_PYTHON from $OVERLAP" >&2
    exit 2
  fi
  OVERLAP_PYTHON=""
  if ! python_probe::find_to OVERLAP_PYTHON "$OVERLAP_FLOOR" 2>/dev/null; then
    echo "error: Python ${OVERLAP_FLOOR}+ not found (tried python3, python) — the native-overlap registry checks cannot run" >&2
    exit 2
  fi

  "$OVERLAP_PYTHON" "$OVERLAP" generate --check || exit 1

  "$OVERLAP_PYTHON" "$OVERLAP" self-check
  overlap_status=$?
  if [[ $overlap_status -eq 1 ]]; then
    echo "Native-overlap registry self-check reported a broken registry." >&2
    exit 1
  elif [[ $overlap_status -eq 3 ]]; then
    echo "Native-overlap registry self-check is degraded (stale-but-honest) — passing with the summary above."
  elif [[ $overlap_status -ne 0 ]]; then
    echo "error: native-overlap self-check exited $overlap_status (usage or environment error)" >&2
    exit 2
  fi
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "error: claude CLI not on PATH (npm install -g @anthropic-ai/claude-code)" >&2
  exit 2
fi

render_validate() {
  local dir="$1"
  shift
  local errfile json status rendered
  errfile="$(mktemp)"
  json="$(claude plugin validate --json "$@" "$dir" 2>"$errfile")"
  status=$?
  if rendered="$(printf '%s' "$json" | node "$SCRIPT_DIR/plugin-validate-report.mjs")"; then
    printf '%s\n' "$rendered"
    if [[ "$status" -ne 0 ]]; then
      cat "$errfile" >&2
    fi
  else
    echo "claude plugin validate --json did not return a report for $dir; falling back to text" >&2
    cat "$errfile" >&2
    claude plugin validate "$@" "$dir"
    status=$?
  fi
  rm -f "$errfile"
  return "$status"
}

validate_one() {
  echo "=== validate ${1%/} ==="
  render_validate "$1"
}

failed=0
buf="$(mktemp -d)" || exit 2
trap 'rm -rf "$buf"' EXIT
pids=()
spawn() {
  local n=${#pids[@]}
  "$@" >"$buf/$n.out" 2>"$buf/$n.err" &
  pids[n]=$!
}
collect() {
  wait "${pids[$1]}" || failed=1
  cat "$buf/$1.out"
  cat "$buf/$1.err" >&2
}

mods=-1
if runs_checked_code "claude plugin test (mods)"; then
  mods=${#pids[@]}
  spawn bash "$SCRIPT_DIR/test-plugin-mods.sh"
fi

width="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
dirs=(plugins/*/)
if ((limited)); then
  dirs=(${only[@]+"${only[@]}"})
  echo "Per-plugin pass limited to ${#only[@]} plugin(s): ${only[*]:-none}"
fi
next=${#pids[@]}
for dir in ${dirs[@]+"${dirs[@]}"}; do
  [[ -d "$dir" ]] || continue
  spawn validate_one "$dir"
  while ((${#pids[@]} - next > width)); do
    collect $((next++))
  done
done
while ((next < ${#pids[@]})); do
  collect $((next++))
done

echo "=== validate --strict (catalog manifest) ==="
render_validate . --strict || failed=1

((mods < 0)) || collect "$mods"

if [[ $failed -ne 0 ]]; then
  echo "Plugin validation failed." >&2
  exit 1
fi
echo "All plugin manifests and the catalog validated."
