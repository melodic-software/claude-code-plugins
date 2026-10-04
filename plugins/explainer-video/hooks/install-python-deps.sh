#!/usr/bin/env bash
# SessionStart hook: install the hash-locked Python packages (requirements.txt) into
# ${CLAUDE_PLUGIN_DATA} on demand, so the produce skill runs against them and nothing fetches a
# package while a skill runs (docs/conventions/on-demand-dependencies, Python). A no-op once the
# set loads. A failed install is a notice on both channels with the repair line, never a silent
# skip. Always exits 0: a failed install must not block the session.
set -uo pipefail

data="${CLAUDE_PLUGIN_DATA:-}"
[[ -n "$data" ]] || exit 0

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ROOT="${SCRIPT_DIR%/*}"

# Loaded only when there is something to report: the common run installs nothing and says nothing.
notice() {
  # shellcheck source=hook-utils.sh
  source "$SCRIPT_DIR/hook-utils.sh"
  hook::emit_skip_notice SessionStart "$1"
}

# launcher_listed -> a python.exe that `py -0p` lists, as a POSIX path: the first tagged 3.12 or 3.13,
# else the first listed, whose pydeps.py says what is required. Only lists: when no runtime is
# installed, the Python install manager installs one on any py launch command.
launcher_listed() {
  local line path first="" re='^[[:space:]]*(-[^[:space:]]+)[[:space:]]+(\*[[:space:]]+)?([A-Za-z]:\\.*\.[Ee][Xx][Ee])'
  while IFS= read -r line; do
    [[ "${line%$'\r'}" =~ $re ]] || continue
    path="$(cygpath -u "${BASH_REMATCH[3]}" 2>/dev/null || printf '%s' "${BASH_REMATCH[3]}")"
    if [[ "${BASH_REMATCH[1]}" =~ ^-(V:)?3\.1[23](-[A-Za-z0-9]+)?$ ]]; then
      printf '%s' "$path"
      return 0
    fi
    [[ -n "$first" ]] || first="$path"
  done < <(py -0p 2>/dev/null </dev/null)
  [[ -n "$first" ]] && printf '%s' "$first"
}

# Any Python starts pydeps.py, which hands over to the first Python 3.12 or 3.13 on PATH or, on
# Windows, listed by the py launcher, and says so when there is none. A zero-length WindowsApps
# python alias opens the Store instead of running: skip it. The Python install manager's py is
# such an alias too, and it runs, so it is only asked to list.
candidates=(python3.13 python3.12 python3 python)
case "${OSTYPE:-}" in
msys* | cygwin*) candidates+=(py) ;;
*) ;;
esac
py=""
for candidate in "${candidates[@]}"; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  if [[ "$candidate" == py ]]; then
    py="$(launcher_listed)" || py=""
    break
  fi
  [[ "$resolved" == *[Ww]indows[Aa]pps* && ! -s "$resolved" ]] && continue
  py="$candidate"
  break
done

if [[ -z "$py" ]]; then
  notice "explainer-video: Python 3.12 or 3.13 was not found on PATH${candidates[4]:+ or listed by the py launcher (py -0p)}, so ManimCE is not installed and /explainer-video:produce will stop. Install Python 3.13 (https://www.python.org/downloads/) and start a new session."
  exit 0
fi

# repair_line -> the install run in the foreground: Windows PowerShell 5.1 under Git Bash or Cygwin
# (call operator, single quotes doubled), a POSIX shell line otherwise, as pydeps.py's own.
repair_line() {
  local parts=("$(command -v "$py")" "$ROOT/scripts/pydeps.py" install --data-dir "$data") line="" part
  case "${OSTYPE:-}" in
  msys* | cygwin*)
    for part in "${parts[@]}"; do
      [[ "$part" == /* ]] && part="$(cygpath -w "$part" 2>/dev/null || printf '%s' "$part")"
      line+=" '${part//\'/\'\'}'"
    done
    printf '&%s' "$line"
    ;;
  *)
    for part in "${parts[@]}"; do
      line+=" '${part//\'/\'\\\'\'}'"
    done
    printf '%s' "${line# }"
    ;;
  esac
}

# to_native <path> -> the path as a native Windows Python reads it. Under Git Bash or Cygwin a POSIX
# path (/c/...) goes through cygpath -m: a session with MSYS path conversion switched off hands it
# over as is, and Python resolves it against the current drive (C:\c\...). Fails rather than
# return the unconverted path.
to_native() {
  case "${OSTYPE:-}" in
  msys* | cygwin*)
    [[ "$1" == /* ]] || {
      printf '%s' "$1"
      return 0
    }
    local converted
    converted="$(cygpath -m "$1" 2>/dev/null)" && [[ -n "$converted" ]] && printf '%s' "$converted"
    ;;
  *) printf '%s' "$1" ;;
  esac
}

if ! script="$(to_native "$ROOT/scripts/pydeps.py")" || ! data_dir="$(to_native "$data")"; then
  notice "explainer-video: cygpath could not convert its pydeps.py or data directory path to Windows form, so ManimCE is not installed and /explainer-video:produce will stop. Check that cygpath runs in Git Bash and start a new session."
  exit 0
fi

if ! out="$("$py" "$script" install --data-dir "$data_dir" </dev/null 2>&1)"; then
  if [[ "$out" == *Traceback* ]]; then
    last="${out//$'\r'/}"
    last="${last##*$'\n'}"
    notice "explainer-video: the Python handover failed: $last; repair with: $(repair_line)"
  else
    notice "explainer-video: its Python packages (ManimCE) could not be installed, so /explainer-video:produce will stop until they are. $out"
  fi
fi
exit 0
