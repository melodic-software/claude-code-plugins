#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PLUGIN_ROOT
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

WORK="${PERF_HARNESS_TEST_ROOT:-$HOME/.cache/performance-harness-tests}/resolve-python.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

capture bash "$SCRIPT_DIR/resolve-python.sh"
assert_eq "resolve-python exits 0 where a Python runs" "0" "$RUN_RC"
assert_contains "resolve-python prints an absolute path" "/" "${RUN_OUT:0:1}"

EMPTY_DIR="$WORK/empty-path"
mkdir -p "$EMPTY_DIR"
capture env PATH="$EMPTY_DIR" "$(type -P bash)" "$SCRIPT_DIR/resolve-python.sh"
assert_eq "resolve-python refuses when no Python runs" "2" "$RUN_RC"

PREAMBLE_SKILL="$PLUGIN_ROOT/skills/go-faster/SKILL.md"
PY_LINE="$(grep -m1 'resolve-python.sh' "$PREAMBLE_SKILL")"
assert_contains "the preamble has a PY line" 'PY=' "$PY_LINE"

ODD_ROOT="$WORK/o'brien dir/plugin"
mkdir -p "$ODD_ROOT/scripts"
cp "$SCRIPT_DIR/resolve-python.sh" "$SCRIPT_DIR/harness-lib.sh" "$ODD_ROOT/scripts/"

NON_BASH_RUNS=0
for PREAMBLE_SHELL in sh zsh; do
  PREAMBLE_SHELL_BIN="$(type -P "$PREAMBLE_SHELL" || true)"
  if [[ -z "$PREAMBLE_SHELL_BIN" ]]; then
    echo "SKIP: $PREAMBLE_SHELL not installed"
    continue
  fi
  # shellcheck disable=SC2016  # the single-quoted text is the expansion to evaluate in that shell
  [[ -z "$("$PREAMBLE_SHELL_BIN" -c 'echo "${BASH_VERSION:-}"')" ]] && NON_BASH_RUNS=$((NON_BASH_RUNS + 1))
  capture env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$PREAMBLE_SHELL_BIN" -c "$PY_LINE"
  assert_contains "the preamble prints an absolute interpreter path under $PREAMBLE_SHELL" "PY=/" "$RUN_OUT"
  for ROOT in "$PLUGIN_ROOT" "$ODD_ROOT"; do
    # shellcheck disable=SC2016  # the single-quoted text is the literal placeholder to replace
    RENDERED="${PY_LINE//'${CLAUDE_PLUGIN_ROOT}'/"$ROOT"}"
    capture env -u CLAUDE_PLUGIN_ROOT "$PREAMBLE_SHELL_BIN" -c "$RENDERED"
    assert_contains "the rendered preamble prints an absolute interpreter path under $PREAMBLE_SHELL from $ROOT" "PY=/" "$RUN_OUT"
  done
done
[[ "$NON_BASH_RUNS" -gt 0 ]] || echo "SKIP: no non-bash shell installed; the preamble cases did not discriminate"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: resolve-python"
exit 0
