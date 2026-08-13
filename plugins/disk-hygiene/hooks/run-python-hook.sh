#!/usr/bin/env bash
# Launch disk-hygiene wired hooks through a Python 3 interpreter resolved
# independently of a bare `python3` on PATH (#1504).
#
# Claude Code registers plugin hooks in exec form: the `command` field is
# resolved on PATH with no shell. When `python3` is absent, broken, or resolves
# to the zero-length WindowsApps App Execution Alias stub, both the guard and its
# Stop detector died the same way — the detector could not observe the guard's
# fail-open. This launcher is registered as `bash` (available in Git Bash on
# Windows) and resolves a real interpreter before exec'ing the target script.
#
# When no interpreter resolves:
#   * guard_launch_monitor.py — emit a once-per-run systemMessage on stdout
#     (the detector's only output channel) so the operator sees the blind spot.
#   * destructive_guard.py — exit 0 silently (existing PreToolUse fail-open).
set -uo pipefail

SCRIPT="${1:-}"
shift || true

MODE=unknown
case "$SCRIPT" in
*guard_launch_monitor.py*) MODE=monitor ;;
*destructive_guard.py*) MODE=guard ;;
esac

# Portable WindowsApps path-component check (case-insensitive).
_under_windowsapps() {
  local path_lower
  path_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$path_lower" == *windowsapps* ]]
}

# True when `path` names a zero-length Windows App Execution Alias stub.
_is_store_alias_stub() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  [[ -s "$path" ]] && return 1
  _under_windowsapps "$path"
}

# Echo a runnable Python 3 interpreter path, or return 1.
resolve_python3() {
  local candidate resolved

  for candidate in python3 python; do
    resolved="$(command -v "$candidate" 2>/dev/null)" || continue
    if _is_store_alias_stub "$resolved"; then
      continue
    fi
    if "$resolved" -c 'import sys; sys.exit(0)' 2>/dev/null; then
      printf '%s' "$resolved"
      return 0
    fi
  done

  if command -v py >/dev/null 2>&1; then
    resolved="$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null)" || return 1
    if [[ -n "$resolved" ]] && "$resolved" -c 'import sys; sys.exit(0)' 2>/dev/null; then
      printf '%s' "$resolved"
      return 0
    fi
  fi

  return 1
}

PYTHON=""
if ! PYTHON="$(resolve_python3)"; then
  PYTHON=""
fi

if [[ -z "$PYTHON" ]]; then
  if [[ "$MODE" == "monitor" ]]; then
    printf '%s\n' \
      '{"systemMessage":"disk-hygiene: destructive guard could not launch — no Python 3 interpreter resolved on this host (python3 missing or is a Windows App Execution Alias stub). Destructive Bash/PowerShell commands may have proceeded unguarded."}'
  fi
  exit 0
fi

exec "$PYTHON" "$SCRIPT" "$@"
