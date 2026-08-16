#!/usr/bin/env bash
# Launch every disk-hygiene hook through a Python 3 interpreter resolved
# independently of a bare `python3` on PATH (#1504) — the two wired hooks in
# hooks.json and, since #2568, the clean skill's frontmatter belt.
#
# When `python3` is absent, broken, or resolves to the zero-length WindowsApps
# App Execution Alias stub, both the guard and its Stop detector died the same
# way — the detector could not observe the guard's fail-open. This launcher
# resolves a real interpreter before exec'ing the target script.
#
# Every caller invokes this file in SHELL FORM — the `command` string names this
# script by path and carries its arguments, with no `args` key. Claude Code
# routes shell form through Git Bash on Windows, resolved by Claude Code itself.
# It must NOT be registered in exec form: exec form is a bare PATH lookup, and on
# Windows `"command": "bash"` resolves to the WSL relay `System32\bash.exe`
# before Git Bash, failing with `execvpe(/bin/bash) failed` (#1006, regressed by
# #1504), while `"command": "python3"` resolves to the zero-length WindowsApps
# alias stub (#2568). A hook that fails to launch is a non-blocking error, so the
# guard silently enforces nothing.
# The skill-frontmatter belt reaches this launcher the same way, but its command
# string may substitute ONLY `${CLAUDE_PLUGIN_ROOT}`: a skill hook receives no
# `${CLAUDE_PLUGIN_DATA}` or `${user_config.*}`, and either makes Claude Code
# refuse the launch outright (#1014).
# Every path placeholder in the command string must stay double-quoted; the
# shell re-tokenizes the string, and plugin roots contain spaces.
#
# When no interpreter resolves:
#   * guard_launch_monitor.py — emit a once-per-run systemMessage on stdout
#     (the detector's only output channel) so the operator sees the blind spot.
#   * destructive_guard.py — exit 0 silently (existing PreToolUse fail-open).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/../skills/clean/scripts/hygiene.py"
# One read of the engine, stopped at the MIN_PYTHON line (#2853). This launcher
# sits behind an always-on `Bash|PowerShell` PreToolUse matcher, so every shell
# tool call pays whatever happens here; the previous form ran TWO separate sed
# passes and neither stopped at the match, scanning the whole ~3,500-line
# engine twice to recover a constant that sits near the top of the file.
#
# The ADDRESS BLOCK is what makes it stop. The obvious one-liner
# `sed -n 's/^MIN_PYTHON = (...).*/\1 \2/p;/^MIN_PYTHON/q'` does NOT quit: by
# the time `q`'s address is evaluated, `s///` has already rewritten the pattern
# space to `3 11`, so `/^MIN_PYTHON/` never matches and sed still reads to EOF.
# Addressing the block on the ORIGINAL line and quitting inside it is what makes
# the read terminate at the match.
#
# First-match-wins is safe because the engine has exactly one `^MIN_PYTHON` line
# (`grep -c '^MIN_PYTHON'` = 1) and test_hygiene.py's VersionFloorTests locks
# both that count and the line's shape. hygiene.MIN_PYTHON remains the single
# origin of the floor (#1028); this refines how it is read, not where it lives.
# hooks/run-python-hook.test.sh holds the one-read + stops-at-the-match contract.
MIN_PYTHON_FLOOR="$(sed -n '/^MIN_PYTHON = (/{s/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1 \2/p;q;}' "$ENGINE")"
MIN_PYTHON_MAJOR=""
MIN_PYTHON_MINOR=""
read -r MIN_PYTHON_MAJOR MIN_PYTHON_MINOR <<<"$MIN_PYTHON_FLOOR" || true
if [[ -z "$MIN_PYTHON_MAJOR" || -z "$MIN_PYTHON_MINOR" ]]; then
  MIN_PYTHON_MAJOR=3
  MIN_PYTHON_MINOR=11
fi
PYTHON_VERSION_PROBE="import sys; raise SystemExit(0 if sys.version_info >= ($MIN_PYTHON_MAJOR, $MIN_PYTHON_MINOR) else 1)"

SCRIPT="${1:-}"
shift || true

MODE=unknown
case "$SCRIPT" in
*guard_launch_monitor.py*) MODE=monitor ;;
*destructive_guard.py*) MODE=guard ;;
*) ;;
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
    if "$resolved" -c "$PYTHON_VERSION_PROBE" 2>/dev/null; then
      printf '%s' "$resolved"
      return 0
    fi
  done

  if command -v py >/dev/null 2>&1; then
    resolved="$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null)" || return 1
    if [[ -n "$resolved" ]] && "$resolved" -c "$PYTHON_VERSION_PROBE" 2>/dev/null; then
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
