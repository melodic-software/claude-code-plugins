#!/usr/bin/env bash
# Tests for preflight.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

PREFLIGHT="$SCRIPT_DIR/preflight.sh"
FAILED=0

rc=0
bash "$PREFLIGHT" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

out="$(bash "$PREFLIGHT" 2>/dev/null)"
code=$?
assert_exit "always exits 0" 0 "$code"
assert_contains "RUNTIME_PROCS label" "$out" "RUNTIME_PROCS:"
assert_contains "RECENT_BUILD label" "$out" "RECENT_BUILD:"
assert_contains "IDE_OPEN label" "$out" "IDE_OPEN:"

if [[ -d /proc/$$ ]] && command -v pgrep >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  PIDS=()
  trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/repoA" "$tmp/repoB" "$tmp/repoAx" "$tmp/other"
  (cd "$tmp/repoA" && exec -a dotnet-fixture-in sleep 60) &
  PIDS+=($!)
  (cd "$tmp/other" && exec -a dotnet-fixture-out sleep 60) &
  PIDS+=($!)
  (cd "$tmp/other" && exec -a "dotnet-fixture-arg $tmp/repoA/src" sleep 60) &
  PIDS+=($!)
  (cd "$tmp/repoAx" && exec -a dotnet-fixture-sib sleep 60) &
  PIDS+=($!)
  sleep 1
  out="$(bash "$PREFLIGHT" "$tmp/repoA" "$tmp/repoB" 2>/dev/null)"
  procs="$(sed -n '/^RUNTIME_PROCS:/,/^RECENT_BUILD:/p' <<<"$out")"
  assert_contains "in-scope cwd process listed" "$procs" "dotnet-fixture-in"
  assert_contains "in-scope process carries its repo" "$procs" "repo: $tmp/repoA"
  assert_contains "cmdline-path process in scope" "$procs" "dotnet-fixture-arg"
  assert_not_contains "out-of-scope process omitted" "$procs" "dotnet-fixture-out"
  assert_not_contains "sibling-prefix dir is out of scope" "$procs" "dotnet-fixture-sib"
  assert_contains "unattributed count reported" "$out" "RUNTIME_PROCS_UNATTRIBUTED: "
  assert_not_contains "unattributed count is nonzero" "$out" "RUNTIME_PROCS_UNATTRIBUTED: 0 "
  assert_contains "IDE_OPEN label with roots" "$out" "IDE_OPEN:"
else
  skip_case "scoped RUNTIME_PROCS cases need /proc and pgrep"
fi

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: preflight.sh tests passed"
