#!/usr/bin/env bash
set -uo pipefail
set -h

_SOURCE_DIR="${BASH_SOURCE[0]%/*}"
if [[ "$_SOURCE_DIR" == "${BASH_SOURCE[0]}" ]]; then
  _SOURCE_DIR="."
fi
case "$_SOURCE_DIR" in
/* | ?:[/\\]*) SCRIPT_DIR="$_SOURCE_DIR" ;;
*) SCRIPT_DIR="$(cd "$_SOURCE_DIR" && pwd)" ;;
esac
ENGINE="$SCRIPT_DIR/../skills/clean/scripts/hygiene.py"

PYTHON_VERSION_PROBE='
import os, re, sys
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
if sys.version_info < floor:
    raise SystemExit(1)
sys.stdout.buffer.write(os.fsencode(sys.executable) + b"\n")
'

MARKER_ROOT=""
LAUNCH_MARKER_SUBDIR=""
SKIP_MARKER_SUBDIR=""
ONLY_SKILL=""
unset DISK_HYGIENE_UNWRITTEN_MARKER
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
  --only-skill)
    ONLY_SKILL="${2:-}"
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
*destructive_guard.py*) MODE=guard ;;
*engine_context.py*) MODE=context ;;
*) ;;
esac

# shellcheck disable=SC2016  # the literal placeholder, deliberately unexpanded
_DATA_ROOT_PLACEHOLDER='${CLAUDE_PLUGIN_DATA}'
_MARKER_PATHS=()
_TMP_MARKER_DIR=""
_PAYLOAD=""
_SESSION_ID=""
_BUFFERED_STDIN=0

_read_payload() {
  _BUFFERED_STDIN=1
  IFS= read -r -d '' _PAYLOAD || true
  local field='"session_id"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
  local anchored="^[[:space:]]*[{][[:space:]]*$field"
  if [[ "$_PAYLOAD" =~ $anchored ]] || [[ "$_PAYLOAD" =~ $field ]]; then
    _SESSION_ID="${BASH_REMATCH[1]}"
  fi
}

_marker_candidates() {
  local subdir="$1" session="$2" suffix="${3:-launched}"
  local safe="${session//[^a-zA-Z0-9_-]/_}"
  _MARKER_PATHS=()
  [[ -n "$safe" ]] || return 1
  if [[ -n "$MARKER_ROOT" && "$MARKER_ROOT" != "$_DATA_ROOT_PLACEHOLDER" ]]; then
    _MARKER_PATHS+=("$MARKER_ROOT/$subdir/$safe.$suffix")
  fi
  _TMP_MARKER_DIR="${TMPDIR:-/tmp}/disk-hygiene-$subdir"
  _MARKER_PATHS+=("$_TMP_MARKER_DIR/$safe.$suffix")
}

_owned_marker_dir() {
  [[ -d "$1" && ! -L "$1" && -O "$1" ]]
}

_trusted_marker_dir() {
  [[ "$1" != "$_TMP_MARKER_DIR" ]] || _owned_marker_dir "$1"
}

_LAUNCH_TOKEN_PATTERN=$'^[0-9]{1,15}-[0-9]{1,10}-[0-9]{1,5}\n?$'

_launch_seen() {
  local launched="" seen=""
  [[ -f "$1.launched" && -r "$1.launched" && -f "$1.seen" && -r "$1.seen" ]] || return 1
  IFS= read -r -d '' launched 2>/dev/null <"$1.launched"
  [[ "$launched" =~ $_LAUNCH_TOKEN_PATTERN ]] || return 1
  IFS= read -r -d '' seen 2>/dev/null <"$1.seen"
  [[ "$seen" == "$launched" ]]
}

if [[ -n "$SKIP_MARKER_SUBDIR" ]]; then
  _read_payload
  if [[ -n "$_SESSION_ID" ]] && _marker_candidates "$SKIP_MARKER_SUBDIR" "$_SESSION_ID"; then
    _marker_unseen=0
    _marker_dir_seen=0
    for _marker_path in "${_MARKER_PATHS[@]}"; do
      _trusted_marker_dir "${_marker_path%/*}" || continue
      [[ -d "${_marker_path%/*}" ]] && _marker_dir_seen=1
      if [[ -f "$_marker_path" ]] && ! _launch_seen "${_marker_path%.launched}"; then
        _marker_unseen=1
        break
      fi
    done
    if ((_marker_dir_seen && !_marker_unseen)); then
      exit 0
    fi
  fi
fi

_skill_selected() {
  [[ -n "$ONLY_SKILL" ]] || return 0
  local key='"skill"[[:space:]]*:[[:space:]]*"/?'
  [[ "$_PAYLOAD" =~ $key"$ONLY_SKILL"\" ]]
}

if [[ -n "$LAUNCH_MARKER_SUBDIR" ]]; then
  ((_BUFFERED_STDIN)) || _read_payload
  if [[ -n "$_SESSION_ID" ]] && _skill_selected &&
    _marker_candidates "$LAUNCH_MARKER_SUBDIR" "$_SESSION_ID"; then
    printf -v _launch_token '%(%s)T' -1
    _launch_token+="-$$-$RANDOM"
    _unwritten_marker=""
    for _marker_path in "${_MARKER_PATHS[@]}"; do
      _marker_dir="${_marker_path%/*}"
      _seen_path="${_marker_path%.launched}.seen"
      # `mkdir` and the `.seen` removal are the only spawns on this path, each
      # behind a builtin `[[ -e ]]`: `mkdir` once per root, the removal once per
      # launch that follows a Stop the monitor recorded. Only the marker
      # directory itself needs mode 700; its parent is `$TMPDIR` or the data root.
      # shellcheck disable=SC2174
      [[ -e "$_marker_dir" || -L "$_marker_dir" ]] ||
        mkdir -p -m 700 "$_marker_dir" 2>/dev/null || continue
      _trusted_marker_dir "$_marker_dir" || continue
      if [[ -e "$_seen_path" || -L "$_seen_path" ]]; then
        rm -f -- "$_seen_path" 2>/dev/null
      fi
      if : >"$_marker_path" 2>/dev/null; then
        printf '%s\n' "$_launch_token" >>"$_marker_path" 2>/dev/null
        _unwritten_marker=""
        break
      fi
      if [[ -z "$_unwritten_marker" ]] && [[ -e "$_seen_path" || -L "$_seen_path" ]]; then
        _unwritten_marker="$_marker_path"
      fi
    done
    if [[ -n "$_unwritten_marker" ]]; then
      export DISK_HYGIENE_UNWRITTEN_MARKER="$_unwritten_marker"
    fi
  fi
fi

[[ -n "$SCRIPT" ]] || exit 0

_is_store_alias_stub() {
  [[ -f "$1" && ! -s "$1" && "${1,,}" == *windowsapps* ]]
}

_interpreter_shaped() {
  local base="${1##*/}"
  base="${base##*\\}"
  case "${base,,}" in
  python3 | python | py | python3.* | python.exe | py.exe) return 0 ;;
  *) return 1 ;;
  esac
}

_use_probed_executable() {
  local exe="${1%$'\r'}"
  [[ "$exe" != *$'\n'* && -x "$exe" && -s "$exe" ]] && _interpreter_shaped "$exe" && PYTHON="$exe"
}

_lookup() {
  _LOOKUP=""
  hash "$1" 2>/dev/null && _LOOKUP="${BASH_CMDS[$1]}"
  return 0
}

resolve_python3() {
  local candidate exe
  PYTHON=""
  _LOOKUPS=()

  for candidate in python3 python; do
    _lookup "$candidate"
    _LOOKUPS+=("$candidate|$_LOOKUP")
    [[ -n "$_LOOKUP" ]] || continue
    _is_store_alias_stub "$_LOOKUP" && continue
    exe="$("$_LOOKUP" -c "$PYTHON_VERSION_PROBE" "$ENGINE" 2>/dev/null)" || continue
    PYTHON="$_LOOKUP"
    _use_probed_executable "$exe"
    return 0
  done

  _lookup py
  _LOOKUPS+=("py|$_LOOKUP")
  [[ -n "$_LOOKUP" ]] || return 1
  exe="$("$_LOOKUP" -3 -c "$PYTHON_VERSION_PROBE" "$ENGINE" 2>/dev/null)" || return 1
  _use_probed_executable "$exe"
}

_CACHE_SCHEMA=2
_CACHE_TTL_SECONDS=86400

_CACHE_FILE=""
_RESOLVED_INTERPRETER=""
_LOOKUP=""
_LOOKUPS=()

_cache_file_path() {
  _CACHE_FILE=""
  local home="${HOME:-}"
  [[ -n "$home" && -d "$home" ]] || return 1
  local key="${SCRIPT_DIR//[^a-zA-Z0-9]/_}"
  if ((${#key} > 96)); then
    key="${key:${#key}-96}"
  fi
  _CACHE_FILE="$home/.cache/disk-hygiene/interpreter-$key"
}

_cached_python3() {
  local file="$1"
  _RESOLVED_INTERPRETER=""
  [[ -f "$file" && -r "$file" ]] || return 1
  local schema="" interp="" written="" line entry name
  local -a lookups=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
    "schema="*) schema="${line#schema=}" ;;
    "written="*) written="${line#written=}" ;;
    "interpreter="*) interp="${line#interpreter=}" ;;
    "lookup="*) lookups+=("${line#lookup=}") ;;
    *) ;;
    esac
  done <"$file"

  [[ "$schema" == "$_CACHE_SCHEMA" ]] || return 1
  ((${#lookups[@]})) || return 1
  for entry in "${lookups[@]}"; do
    name="${entry%%|*}"
    case "$name" in
    python3 | python | py) ;;
    *) return 1 ;;
    esac
    _lookup "$name"
    [[ "$_LOOKUP" == "${entry#*|}" ]] || return 1
    [[ -z "$_LOOKUP" || ! "$_LOOKUP" -nt "$file" ]] || return 1
  done
  [[ -n "$interp" && -x "$interp" && -s "$interp" ]] || return 1
  _interpreter_shaped "$interp" || return 1
  [[ ! "$interp" -nt "$file" ]] || return 1
  [[ "$written" =~ ^[0-9]+$ ]] || return 1
  local now
  printf -v now '%(%s)T' -1
  ((now >= written)) || return 1
  ((now - written < _CACHE_TTL_SECONDS)) || return 1
  _RESOLVED_INTERPRETER="$interp"
}

_store_python3() {
  local file="$1" interp="$2" dir temp now entry
  for entry in "$interp" "${_LOOKUPS[@]}"; do
    [[ "$entry" != *$'\n'* ]] || return 0
  done
  dir="${file%/*}"
  [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || return 0
  chmod 700 "$dir" 2>/dev/null || true
  printf -v now '%(%s)T' -1
  temp="$file.$$.tmp"
  {
    printf 'schema=%s\n' "$_CACHE_SCHEMA"
    printf 'written=%s\n' "$now"
    printf 'interpreter=%s\n' "$interp"
    printf 'lookup=%s\n' "${_LOOKUPS[@]}"
  } >"$temp" 2>/dev/null && mv -f "$temp" "$file" 2>/dev/null ||
    rm -f "$temp" 2>/dev/null || true
  return 0
}

PYTHON=""
_cache_file_path || true

if [[ -n "$_CACHE_FILE" ]] && _cached_python3 "$_CACHE_FILE"; then
  PYTHON="$_RESOLVED_INTERPRETER"
fi

if [[ -z "$PYTHON" ]]; then
  resolve_python3 || PYTHON=""
  if [[ -n "$PYTHON" && -n "$_CACHE_FILE" ]]; then
    _store_python3 "$_CACHE_FILE" "$PYTHON"
  fi
fi

_NO_PYTHON='no usable Python 3 (python3, python, py -3)'
_CHECKER_ROOT="${SCRIPT_DIR%/*}"
_CHECKER_ROOT="${_CHECKER_ROOT//\\//}"
_CHECKER_ROOT="${_CHECKER_ROOT//\"/}"
_NO_PYTHON_FIX="Install Python 3 ahead of WindowsApps on PATH; diagnose with: node '$_CHECKER_ROOT/lib/prerequisites.mjs' check '$_CHECKER_ROOT'"

_guard_mode_value() {
  local -a argv=("$@")
  local i
  _MODE_VALUE=""
  for ((i = 0; i < ${#argv[@]}; i++)); do
    if [[ "${argv[i]}" == "--mode" ]] && ((i + 1 < ${#argv[@]})); then
      _MODE_VALUE="${argv[i + 1]}"
      return 0
    fi
    if [[ "${argv[i]}" == --mode=* ]]; then
      _MODE_VALUE="${argv[i]#--mode=}"
      return 0
    fi
  done
}

_no_python_noticed() {
  local path dir
  [[ -n "$_SESSION_ID" ]] || return 1
  _marker_candidates guard-no-interpreter "$_SESSION_ID" noticed || return 1
  for path in "${_MARKER_PATHS[@]}"; do
    _owned_marker_dir "${path%/*}" && [[ -f "$path" ]] && return 0
  done
  for path in "${_MARKER_PATHS[@]}"; do
    dir="${path%/*}"
    # shellcheck disable=SC2174  # only the marker directory needs mode 700
    [[ -e "$dir" || -L "$dir" ]] || mkdir -p -m 700 "$dir" 2>/dev/null || continue
    _owned_marker_dir "$dir" || continue
    : >"$path" 2>/dev/null && break
  done
  return 1
}

_guard_without_python() {
  _guard_mode_value "$@"
  if [[ "$_MODE_VALUE" != "engine-gate" ]]; then
    printf '%s\n' "disk-hygiene: denied: $_NO_PYTHON, so the /disk-hygiene:clean belt cannot check any Bash or PowerShell call. $_NO_PYTHON_FIX" >&2
    exit 2
  fi
  ((_BUFFERED_STDIN)) || _read_payload
  if [[ -z "${_PAYLOAD//[[:space:]]/}" || "${_PAYLOAD,,}" == *hygiene.py* ]]; then
    printf '%s\n' "disk-hygiene: denied: $_NO_PYTHON, so this hygiene.py call cannot be checked. $_NO_PYTHON_FIX" >&2
    exit 2
  fi
  _no_python_noticed && exit 0
  printf '{"systemMessage":"%s"}\n' \
    "disk-hygiene: $_NO_PYTHON; hygiene.py commands are denied this session. $_NO_PYTHON_FIX"
  exit 0
}

if [[ -z "$PYTHON" ]]; then
  case "$MODE" in
  guard) _guard_without_python "$@" ;;
  context)
    printf '{"decision":"block","reason":"%s"}\n' \
      "disk-hygiene: /disk-hygiene:clean cannot run: $_NO_PYTHON. $_NO_PYTHON_FIX"
    ;;
  monitor)
    ((_BUFFERED_STDIN)) || _read_payload
    _no_python_noticed && exit 0
    printf '{"systemMessage":"%s"}\n' \
      "disk-hygiene: $_NO_PYTHON, so this session's guarded calls were denied or ran unchecked. $_NO_PYTHON_FIX"
    ;;
  *) ;;
  esac
  exit 0
fi

if ((_BUFFERED_STDIN)); then
  exec "$PYTHON" "$SCRIPT" "$@" <<<"$_PAYLOAD"
fi

exec "$PYTHON" "$SCRIPT" "$@"
