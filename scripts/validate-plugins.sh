#!/usr/bin/env bash
# Validate every plugin manifest and the marketplace catalog with the Claude Code CLI.
#
# Requires `claude` on PATH (npm install -g @anthropic-ai/claude-code). The
# per-plugin pass catches a bad plugins/<name>/.claude-plugin/plugin.json; the
# --strict repo-root pass validates the catalog manifest itself, where a bad
# marketplace.json entry surfaces (it is not caught by per-plugin validation).
# A plugin that ships a mod also gets `claude plugin test` (scripts/test-plugin-mods.sh),
# which skips when the CLI predates mods.
#
#   scripts/validate-plugins.sh                    every plugin
#   scripts/validate-plugins.sh --only "<names>"   the per-plugin pass for the
#                                                  space-separated plugins only,
#                                                  none when the list is empty;
#                                                  every repository-wide check
#                                                  (contracts, catalog, the
#                                                  --strict catalog pass, mods)
#                                                  still runs
#
# CI passes the plugins a diff touched: each per-plugin pass reads only its own
# directory, so an untouched plugin's verdict is the one its last green run gave.
# A name that is not a plugin directory is an error, not a quiet skip.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

limited=0
only=()
case "${1:-}" in
'') ;;
--only)
  [[ $# -eq 2 ]] || {
    echo "usage: validate-plugins.sh [--only \"<plugin> ...\"]" >&2
    exit 2
  }
  limited=1
  for name in $2; do
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ || ! -d "plugins/$name" ]]; then
      echo "error: '$name' is not a plugin under plugins/" >&2
      exit 2
    fi
    only+=("plugins/$name/")
  done
  ;;
*)
  echo "usage: validate-plugins.sh [--only \"<plugin> ...\"]" >&2
  exit 2
  ;;
esac

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not on PATH" >&2
  exit 2
fi
node scripts/validate-plugin-contracts.mjs || exit 1
bash scripts/check-publisher-token-alignment.sh || exit 1
node scripts/generate-catalog.mjs --check || exit 1
node scripts/generate-cheatsheet.mjs --check || exit 1
node plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs --check || exit 1

# --- native-overlap registry: generated-view drift + freshness self-check ----
#
# The engine is Python, so the interpreter is resolved through the repo's
# candidate loop rather than a bare `python3` call: a zero-length candidate
# under a WindowsApps path component is the Store's App Execution Alias stub,
# and executing it opens the Microsoft Store or hangs instead of running an
# interpreter.
OVERLAP="plugins/harness-ops/skills/audit-native-overlap/scripts/overlap.py"
OVERLAP_FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$OVERLAP")"
if [[ -z "$OVERLAP_FLOOR" ]]; then
  echo "error: could not parse MIN_PYTHON from $OVERLAP" >&2
  exit 2
fi
OVERLAP_PYTHON=""
for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  if "$candidate" -c "import sys; floor = tuple(int(part) for part in '$OVERLAP_FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" 2>/dev/null; then
    OVERLAP_PYTHON="$candidate"
    break
  fi
done
if [[ -z "$OVERLAP_PYTHON" ]]; then
  echo "error: Python ${OVERLAP_FLOOR}+ not found (tried python3, python) — the native-overlap registry checks cannot run" >&2
  exit 2
fi

"$OVERLAP_PYTHON" "$OVERLAP" generate --check || exit 1

# Exit-3 policy, stated here because it is a decision and not an oversight: the
# self-check exits 0 ok / 1 broken / 3 degraded (2 stays argparse's usage
# error). Degraded means the data is stale-but-honest or a comparison was not
# locally decidable — an upstream release the registry does not own, or no
# `claude` on PATH. Neither is a defect this repo can fix by editing the store,
# and a chronically red gate on such a condition trains people to ignore it. So
# broken fails the gate and degraded prints its summary and passes.
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

if ! command -v claude >/dev/null 2>&1; then
  echo "error: claude CLI not on PATH (npm install -g @anthropic-ai/claude-code)" >&2
  exit 2
fi

# --json (Claude Code >= 2.1.259) is one object: success, strict, target,
# manifest, and contents[] of per-file errors, warnings, and notes. The
# renderer exits 2 when stdout is not that object, and this loop then falls
# back to the text command so a CLI older than the flag still validates.
# Basis: https://code.claude.com/docs/en/plugins/cli-reference#plugin-validate
render_validate() {
  local dir="$1"
  shift
  local errfile json status rendered
  errfile="$(mktemp)"
  json="$(claude plugin validate --json "$@" "$dir" 2>"$errfile")"
  status=$?
  if rendered="$(printf '%s' "$json" | node scripts/plugin-validate-report.mjs)"; then
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

failed=0
dirs=(plugins/*/)
if ((limited)); then
  dirs=(${only[@]+"${only[@]}"})
  echo "Per-plugin pass limited to ${#only[@]} plugin(s): ${only[*]:-none}"
fi
for dir in ${dirs[@]+"${dirs[@]}"}; do
  [[ -d "$dir" ]] || continue
  echo "=== validate ${dir%/} ==="
  render_validate "$dir" || failed=1
done

echo "=== validate --strict (catalog manifest) ==="
render_validate . --strict || failed=1

bash scripts/test-plugin-mods.sh || failed=1

if [[ $failed -ne 0 ]]; then
  echo "Plugin validation failed." >&2
  exit 1
fi
echo "All plugin manifests and the catalog validated."
