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

# --- optional per-session launch marker ------------------------------------
#
# Three OPTIONAL leading flags, consumed here and never forwarded to Python:
#
#   --marker-root <dir>            root the marker tree lives under, spelled
#                                  `"${CLAUDE_PLUGIN_DATA}"` by every caller;
#   --launch-marker <subdir>       write `<root>/<subdir>/<session>.launched`
#                                  BEFORE exec'ing the target;
#   --skip-unless-marker <subdir>  exit 0 without exec'ing anything when at
#                                  least one candidate directory exists and
#                                  none of them holds that file.
#
# Together they let a `Stop` hook cost nothing in a session where the hook it
# watches never ran. `guard_launch_monitor.py` reports failures of the
# `PreToolUse` guard, and the guard rows are `if`-gated on the engine's file
# name, so most sessions never launch the guard at all — yet the monitor still
# started a whole Python on every turn to discover that. `Stop` rows accept
# neither `matcher` nor `if`, so the only place that gate can live is here.
#
# The root is passed EXPLICITLY rather than read from `CLAUDE_PLUGIN_DATA` in
# the environment: a hook subprocess can inherit that variable naming a
# DIFFERENT plugin's data directory, and a writer and a reader that disagree
# about the root skip silently, which is the missed-detection failure this
# monitor exists to prevent. An empty value, or an unsubstituted literal
# `${CLAUDE_PLUGIN_DATA}`, is treated as absent (the placeholder idiom
# `guard_launch_monitor.py` already uses) and the tmp fallback carries the
# marker alone.
#
# Failure modes, stated rather than implied:
#   * a marker is per session and is never removed. Under the tmp fallback the
#     OS clears it; under `--marker-root` it is one empty file per session that
#     launched a guard, and neither the clean engine nor `lib/guard_decision_log.py`
#     runs a retention sweep over the plugin data root that could collect them.
#   * a session whose guard rows never fired is skipped BY DESIGN: there is no
#     guard invocation for the monitor to have found a failure of.
#   * a hook that failed before this script ran leaves no marker and is not this
#     monitor's to detect — the detector reads the transcript for the guard's
#     own command string, which such a failure still records.
#   * the marker is written before the interpreter is even resolved, so the
#     failure the monitor DOES exist to catch — the guard launching and dying —
#     still leaves the marker that keeps the monitor running.
#   * the session id is recovered with a regex over the raw payload rather than
#     a JSON parse, because a parse is the Python this gate exists to avoid.
#     The match is anchored to the payload's opening key, which nothing further
#     in the payload can reach; only a payload that does not open with
#     `session_id` falls back to an unanchored match, where a NESTED
#     `session_id` key could win instead and key the marker wrongly. Both rows
#     parse identically, so that corner is a missed detection, never a false
#     alarm.
#   * a misparse fails SAFE: no session id means write nothing and skip
#     nothing, which is this launcher's behavior before these flags existed.
#   * a launch that could create NEITHER candidate directory leaves no marker
#     at all, and a Stop that read only the marker file would then silence the
#     monitor for the whole session: a silent failure in the one detector that
#     exists to catch silent failures. So the skip is gated on a candidate
#     DIRECTORY existing. With none, the Stop row falls through and runs the
#     monitor, which is the behavior before these flags existed. The cost of
#     that fail-open is that the skip is inert in a plugin data root where no
#     guard has ever launched: every Stop pays the old price until the first
#     guard launch spends its one `mkdir`.
#   * RESIDUAL, and undetectable across processes: a candidate directory that
#     exists while the marker FILE could not be written (a full disk, a
#     permission denial on the file alone) still degrades to silence for that
#     session. The file that failed is the only channel between the launch row
#     and the Stop row, so the Stop row cannot tell that case apart from a
#     session whose guard rows never fired.
MARKER_ROOT=""
LAUNCH_MARKER_SUBDIR=""
SKIP_MARKER_SUBDIR=""
while (($#)); do
  case "$1" in
  --marker-root)
    MARKER_ROOT="${2:-}"
    shift 2 || break
    ;;
  --launch-marker)
    LAUNCH_MARKER_SUBDIR="${2:-}"
    shift 2 || break
    ;;
  --skip-unless-marker)
    SKIP_MARKER_SUBDIR="${2:-}"
    shift 2 || break
    ;;
  *) break ;;
  esac
done

SCRIPT="${1:-}"
shift || true

MODE=unknown
case "$SCRIPT" in
*guard_launch_monitor.py*) MODE=monitor ;;
*) ;;
esac

# shellcheck disable=SC2016  # the literal placeholder, deliberately unexpanded
_DATA_ROOT_PLACEHOLDER='${CLAUDE_PLUGIN_DATA}'
_MARKER_PATHS=()
_PAYLOAD=""
_SESSION_ID=""
_BUFFERED_STDIN=0

# Buffer the whole hook payload into a variable and recover its session id.
# `read` is a builtin, so buffering costs no process; the payload is handed to
# Python on a here-string at `exec` time, leaving its stdin unchanged.
_read_payload() {
  _BUFFERED_STDIN=1
  IFS= read -r -d '' _PAYLOAD || true
  local field='"session_id"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
  # Anchored first. The hooks reference shows `session_id` as the payload's
  # opening key for every event but documents no ordering guarantee, and the
  # payload nests objects of its own (`tool_input`) that could carry the same
  # key name. An anchored match cannot be reached by either; the unanchored
  # fallback runs only for a payload that did NOT open with the field, and keeps
  # a reordered payload from turning this gate into a silent no-op.
  local anchored="^[[:space:]]*[{][[:space:]]*$field"
  if [[ "$_PAYLOAD" =~ $anchored ]] || [[ "$_PAYLOAD" =~ $field ]]; then
    _SESSION_ID="${BASH_REMATCH[1]}"
  fi
}

# Fill `_MARKER_PATHS` with the candidates for one subdir, most-preferred
# first, mirroring `guard_launch_monitor.py`'s own `_marker_path_candidates`:
# the data root when one resolved, then a tmp fallback whose directory name is
# built from the subdir, so a `.launched` marker sits beside the `.warned` one
# the monitor writes. Only bash reads and writes `.launched`, so the tmp
# directory need not be the one Python's `tempfile.gettempdir()` picks; what
# matters is that both flags resolve it identically, which they do.
_marker_candidates() {
  local subdir="$1" session="$2"
  local safe="${session//[^a-zA-Z0-9_-]/_}"
  _MARKER_PATHS=()
  [[ -n "$safe" ]] || return 1
  if [[ -n "$MARKER_ROOT" && "$MARKER_ROOT" != "$_DATA_ROOT_PLACEHOLDER" ]]; then
    _MARKER_PATHS+=("$MARKER_ROOT/$subdir/$safe.launched")
  fi
  _MARKER_PATHS+=("${TMPDIR:-/tmp}/disk-hygiene-$subdir/$safe.launched")
}

if [[ -n "$SKIP_MARKER_SUBDIR" ]]; then
  _read_payload
  if [[ -n "$_SESSION_ID" ]] && _marker_candidates "$SKIP_MARKER_SUBDIR" "$_SESSION_ID"; then
    _marker_found=0
    # Skipping requires POSITIVE evidence that the launch side got as far as a
    # marker tree. No candidate directory at all is the shape a launch whose
    # `mkdir` failed for every root leaves behind, and silencing the monitor on
    # it would be a silent failure in the detector that exists to catch silent
    # failures. Both tests are builtins, so the skip path still spawns nothing.
    _marker_dir_seen=0
    for _marker_path in "${_MARKER_PATHS[@]}"; do
      [[ -d "${_marker_path%/*}" ]] && _marker_dir_seen=1
      if [[ -f "$_marker_path" ]]; then
        _marker_found=1
        break
      fi
    done
    if ((_marker_dir_seen && !_marker_found)); then
      exit 0
    fi
  fi
fi

if [[ -n "$LAUNCH_MARKER_SUBDIR" ]]; then
  ((_BUFFERED_STDIN)) || _read_payload
  if [[ -n "$_SESSION_ID" ]] && _marker_candidates "$LAUNCH_MARKER_SUBDIR" "$_SESSION_ID"; then
    for _marker_path in "${_MARKER_PATHS[@]}"; do
      _marker_dir="${_marker_path%/*}"
      # `mkdir` is the one spawn on this path and `[[ -d ]]` is a builtin, so it
      # is paid once per root rather than once per launch.
      [[ -d "$_marker_dir" ]] || mkdir -p "$_marker_dir" 2>/dev/null || continue
      : >"$_marker_path" 2>/dev/null && break
    done
  fi
fi

# Portable WindowsApps path-component check (case-insensitive).
_under_windowsapps() {
  [[ "${1,,}" == *windowsapps* ]]
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
  # Split on BOTH separators. The `py -3` fallback resolves through
  # `print(sys.executable)`, which on Windows returns a NATIVE backslash path
  # (`<drive>:\<path>\python.exe`) — and that fallback exists precisely for hosts
  # where neither `python3` nor `python` is on PATH. Stripping only `/` leaves
  # the whole path in `interp_base`, the allowlist below never matches, and the
  # cache misses on every invocation: the warm path would be dead on exactly
  # the host class this branch was written for, silently and with no error.
  local interp_base="${interp##*/}"
  interp_base="${interp_base##*\\}"
  # Case-insensitive: Windows filenames are, and `PYTHON.EXE` is the same file.
  # `python3.*` already covers `python3.exe`, `python3.13` and `python3.13.exe`;
  # spelling those separately is what SC2221/SC2222 flag as dead patterns.
  case "${interp_base,,}" in
  python3 | python | py | python3.* | python.exe | py.exe) ;;
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

# A buffered payload is replayed on a here-string, which bash serves from a pipe
# or a temp file without creating a process. Python reads the same bytes it
# would have read from the inherited stdin, plus the newline `<<<` appends —
# both consumers here (`json.load(sys.stdin)` in the guard, `sys.stdin.read()`
# then `json.loads` in the monitor) ignore trailing whitespace.
if ((_BUFFERED_STDIN)); then
  exec "$PYTHON" "$SCRIPT" "$@" <<<"$_PAYLOAD"
fi

exec "$PYTHON" "$SCRIPT" "$@"
