#!/usr/bin/env bash
# Launch every disk-hygiene hook through a Python 3 interpreter resolved
# independently of a bare `python3` on PATH (#1504) — the two wired hooks in
# hooks.json and the clean skill's frontmatter belt.
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

# `$(cd ... && pwd)` forks twice (command substitution plus `dirname`) on a path
# every registered caller already passes ABSOLUTE — hooks.json and the skill
# frontmatter both spell it `"${CLAUDE_PLUGIN_ROOT}"/hooks/run-python-hook.sh`.
# Strip the trailing component with parameter expansion in that case and keep
# the fork for the relative spelling (a test harness, or a hand `./` run), which
# is the only one that needs normalising.
_SOURCE_DIR="${BASH_SOURCE[0]%/*}"
if [[ "$_SOURCE_DIR" == "${BASH_SOURCE[0]}" ]]; then
  _SOURCE_DIR="."
fi
case "$_SOURCE_DIR" in
/* | ?:[/\\]*) SCRIPT_DIR="$_SOURCE_DIR" ;;
*) SCRIPT_DIR="$(cd "$_SOURCE_DIR" && pwd)" ;;
esac
ENGINE="$SCRIPT_DIR/../skills/clean/scripts/hygiene.py"

# Interpreter resolution is COLD-PATH ONLY (#3502). This launcher sits behind an
# always-on `Bash|PowerShell` PreToolUse matcher, so every shell tool call in
# every session pays whatever happens here — and what happened here was 2-3
# extra process spawns before the guard even started: a `sed` read of the engine
# to recover `MIN_PYTHON`, a whole extra Python launched solely to evaluate a
# version predicate, and on the `py` branch a third. Process creation is the
# dominant cost on Windows (EDR scans every image), and it is the term that
# explodes under concurrent load, which is exactly when the guard's own watchdog
# was firing and denying benign read-only commands.
#
# The resolution logic itself is unchanged and still runs whenever the cache
# does not answer — it exists for real reasons (WindowsApps App Execution Alias
# stubs, the `py` launcher fallback, the minimum-version floor). It just no
# longer runs on every invocation.
#
# `PYTHON_VERSION_PROBE` now recovers the floor from the engine ITSELF, inside
# the candidate interpreter, so the cold path spends ONE spawn per candidate
# instead of a `sed` plus a Python. `hygiene.MIN_PYTHON` remains the single
# origin of the floor (#1028) — this changes who reads it, not where it lives —
# and the hardcoded fallback below still applies when the engine is unreadable.
PYTHON_VERSION_PROBE='
import re, sys
floor = (3, 11)
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        for line in handle:
            found = re.match(r"^MIN_PYTHON = \((\d+), (\d+)\)$", line.rstrip("\n"))
            if found:
                floor = (int(found.group(1)), int(found.group(2)))
                break
except OSError:
    pass
raise SystemExit(0 if sys.version_info >= floor else 1)
'

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
    if "$resolved" -c "$PYTHON_VERSION_PROBE" "$ENGINE" 2>/dev/null; then
      printf '%s' "$resolved"
      return 0
    fi
  done

  if command -v py >/dev/null 2>&1; then
    resolved="$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null)" || return 1
    if [[ -n "$resolved" ]] && "$resolved" -c "$PYTHON_VERSION_PROBE" "$ENGINE" 2>/dev/null; then
      printf '%s' "$resolved"
      return 0
    fi
  fi

  return 1
}

# --- resolved-interpreter cache -------------------------------------------
#
# The hot path must reach `exec` with ZERO extra process spawns, so every check
# below is a bash BUILTIN (`[[ -x ]]`, `[[ -s ]]`, `[[ -nt ]]`, `read`,
# `printf '%(%s)T'`). Anything that shells out here would reintroduce the cost
# this cache exists to remove.
#
# Cache location is derived from `$HOME` and this script's own directory and
# NOTHING else. That is a hard constraint, not a preference: the skill-
# frontmatter registration may substitute only `${CLAUDE_PLUGIN_ROOT}` — a skill
# hook receives no `${CLAUDE_PLUGIN_DATA}` and no `${user_config.*}`, and either
# makes Claude Code refuse the launch outright (#1014). `SCRIPT_DIR` is already
# version-pinned (`.../disk-hygiene/<version>/hooks`), so a plugin upgrade lands
# on a different key and cannot read a stale entry.
#
# INVALIDATION, in the order the hot path checks it:
#   1. schema tag mismatch      — a launcher upgrade rewrote the record shape;
#   2. `PATH` differs verbatim  — a different `python3` may now win the lookup;
#   3. interpreter not executable / zero-length — removed, or replaced by a
#      WindowsApps App Execution Alias stub since the entry was written;
#   4. interpreter NEWER than the cache file (`-nt`) — an in-place upgrade;
#   5. TTL expiry — the backstop for the residual case none of the above sees:
#      a NEW interpreter installed into an existing `PATH` directory with a
#      preserved (older) mtime. Bounded staleness, not correctness, is what the
#      TTL buys; every other shape is caught structurally above.
# Any miss, unreadable record, or malformed field falls through to full
# resolution. A cache failure must never be able to produce "no interpreter" —
# that is the guard's silent fail-open (exit 0, nothing enforced).
_CACHE_SCHEMA=1
# COMPILED IN, deliberately not an environment override. A widened TTL makes
# this launcher accept a record it would otherwise have rejected as stale, so
# the knob is an env-borne input to a security control — the exact shape
# `resolve_disk_hygiene_enabled` refuses on the Python side, because "a repo
# `settings.json` `env` block reaches hook subprocesses and carries no
# provenance a hook could check". A tunable staleness window is not worth a new
# channel of that kind; an operator who needs re-resolution can delete the
# record.
_CACHE_TTL_SECONDS=86400

# Every hot-path helper reports through a GLOBAL rather than stdout. Command
# substitution — `x="$(f)"` — forks a subshell, and a subshell on Windows is a
# real process spawn (MSYS emulates `fork`), which is the exact cost this cache
# exists to remove. Assigning a global keeps the whole hit path in-process.
_CACHE_FILE=""
_RESOLVED_INTERPRETER=""

_cache_file_path() {
  _CACHE_FILE=""
  local home="${HOME:-}"
  [[ -n "$home" && -d "$home" ]] || return 1
  # `PATH` is compared verbatim inside the record; a newline in it would break
  # the line-oriented format, so such an environment simply goes uncached.
  [[ "$PATH" != *$'\n'* ]] || return 1
  local key="${SCRIPT_DIR//[^a-zA-Z0-9]/_}"
  # Bound the filename without `${key: -96}`: a negative offset whose magnitude
  # exceeds the string length yields the EMPTY string in bash, which would
  # collapse every plugin root onto one shared record.
  if ((${#key} > 96)); then
    key="${key:${#key}-96}"
  fi
  _CACHE_FILE="$home/.cache/disk-hygiene/interpreter-$key"
}

# Set `_RESOLVED_INTERPRETER` from a still-valid cache record, or return 1.
# Builtins only — no forks, no spawns.
_cached_python3() {
  local file="$1"
  _RESOLVED_INTERPRETER=""
  [[ -f "$file" && -r "$file" ]] || return 1
  local schema="" cached_path="" interp="" written="" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
    "schema="*) schema="${line#schema=}" ;;
    "written="*) written="${line#written=}" ;;
    "interpreter="*) interp="${line#interpreter=}" ;;
    # PATH last: it is the only field that may itself contain `=`.
    "path="*) cached_path="${line#path=}" ;;
    *) ;;
    esac
  done <"$file"

  [[ "$schema" == "$_CACHE_SCHEMA" ]] || return 1
  [[ "$cached_path" == "$PATH" ]] || return 1
  [[ -n "$interp" && -x "$interp" && -s "$interp" ]] || return 1
  # The hot path `exec`s this value, so the record is an input to a security
  # control and is treated as untrusted: only a basename a resolution would
  # itself have produced is accepted. Pure parameter expansion, so it costs no
  # spawn.
  #
  # KNOWN LIMIT, stated rather than implied. This validates SHAPE, not identity:
  # an executable, non-empty file merely NAMED `python3` is accepted and
  # `exec`'d, the guard never runs, and the hook exits 0 having enforced
  # nothing. Proving the binary is really Python means running it, which is the
  # spawn this cache exists to remove, so the check cannot be strengthened
  # without giving back the win.
  #
  # Reaching that requires writing the record, and the record's location
  # derives from `$HOME` — so unlike the pre-cache launcher, `HOME` is now an
  # input to this control. Two honest readings: if nothing untrusted can set
  # `HOME` for hook subprocesses, this is unreachable; if something can, it is a
  # new instance of an exposure that already exists, since a hostile `PATH`
  # fails open on the pre-cache launcher too (`PYTHON_VERSION_PROBE` only checks
  # an exit status, which any script satisfies). It is NOT a new KIND of
  # channel, and the plugin tree is not writable-adjacent to it, so the "anyone
  # who can write here can already edit the hook registration" argument does not
  # cover it. Recorded so a future reviewer weighs it deliberately.
  local interp_base="${interp##*/}"
  case "${interp_base%.exe}" in
  python3 | python | py | python3.*) ;;
  *) return 1 ;;
  esac
  # An interpreter modified after this record was written is not the one that
  # was validated.
  [[ ! "$interp" -nt "$file" ]] || return 1
  [[ "$written" =~ ^[0-9]+$ ]] || return 1
  local now
  printf -v now '%(%s)T' -1
  ((now >= written)) || return 1
  ((now - written < _CACHE_TTL_SECONDS)) || return 1
  _RESOLVED_INTERPRETER="$interp"
}

# Persist a validated interpreter. Best-effort throughout: a write failure
# leaves the next invocation to re-resolve, which is slow, never wrong.
_store_python3() {
  local file="$1" interp="$2" dir temp now
  dir="${file%/*}"
  [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || return 0
  # Best-effort on POSIX hosts. MSYS `chmod` is close to a no-op against
  # Windows ACLs, so this narrows exposure where it can and is not relied on:
  # the read path validates the record rather than trusting its location.
  chmod 700 "$dir" 2>/dev/null || true
  printf -v now '%(%s)T' -1
  temp="$file.$$.tmp"
  {
    printf 'schema=%s\n' "$_CACHE_SCHEMA"
    printf 'written=%s\n' "$now"
    printf 'interpreter=%s\n' "$interp"
    printf 'path=%s\n' "$PATH"
  } >"$temp" 2>/dev/null || {
    rm -f "$temp" 2>/dev/null || true
    return 0
  }
  # Concurrent hooks race to publish; `mv` is atomic within a filesystem, so the
  # loser's record is replaced rather than interleaved with the winner's.
  mv -f "$temp" "$file" 2>/dev/null || rm -f "$temp" 2>/dev/null || true
  return 0
}

PYTHON=""
_cache_file_path || true

# Hot path: a valid record reaches `exec` having spawned nothing at all.
if [[ -n "$_CACHE_FILE" ]] && _cached_python3 "$_CACHE_FILE"; then
  PYTHON="$_RESOLVED_INTERPRETER"
fi

# Cold path: full resolution, then publish for the next invocation.
if [[ -z "$PYTHON" ]]; then
  if ! PYTHON="$(resolve_python3)"; then
    PYTHON=""
  fi
  if [[ -n "$PYTHON" && -n "$_CACHE_FILE" ]]; then
    _store_python3 "$_CACHE_FILE" "$PYTHON"
  fi
fi

if [[ -z "$PYTHON" ]]; then
  if [[ "$MODE" == "monitor" ]]; then
    printf '%s\n' \
      '{"systemMessage":"disk-hygiene: destructive guard could not launch — no Python 3 interpreter resolved on this host (python3 missing or is a Windows App Execution Alias stub). Destructive Bash/PowerShell commands may have proceeded unguarded."}'
  fi
  exit 0
fi

exec "$PYTHON" "$SCRIPT" "$@"
