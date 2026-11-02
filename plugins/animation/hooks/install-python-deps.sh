#!/usr/bin/env bash
# GENERATED from lib/install-python-deps.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# SessionStart hook: install the plugin's hash-locked Python packages (requirements.txt) into
# ${CLAUDE_PLUGIN_DATA} on demand, so its skills run against them and nothing fetches a package
# while a skill runs (docs/contracts/on-demand-dependencies, Python). A no-op once the set
# loads, and one that starts no process while pydeps.py's ready stamp holds. A failed install is a user notice with the repair line, never a silent skip; the model
# hears nothing here, since pydeps.py run prints the same repair line when a skill runs.
# Always exits 0: a failed install must not block the session. The plugin's wording (its name,
# the Pythons it supports, the skills that need the packages) is in install-python-deps.conf.
set -uo pipefail

data="${CLAUDE_PLUGIN_DATA:-}"
[[ -n "$data" ]] || exit 0

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ROOT="${SCRIPT_DIR%/*}"

# The plugin's wording; the defaults stand only if its conf leaves one out.
PYDEPS_PLUGIN="install-python-deps" PYDEPS_PYTHONS="3.12 or later" PYDEPS_USERS="its skills" PYDEPS_PACKAGES="Python packages"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/install-python-deps.conf"

# Loaded only when there is something to report: the common run installs nothing and says nothing.
notice() {
  # shellcheck source=hook-utils.sh
  source "$SCRIPT_DIR/hook-utils.sh"
  hook::emit_skip_notice SessionStart "" "$1"
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

# Any Python starts pydeps.py, which hands over to the first supported Python on PATH or, on
# Windows, listed by the py launcher, and says so when there is none. A zero-length WindowsApps
# python alias opens the Store instead of running: skip it, and skip a name that resolves but does
# not run, such as a pyenv shim for a version not enabled. The Python install manager's py is
# such an alias too, and it runs, so it is only asked to list.
candidates=(python3.13 python3.12 python3 python)
case "${OSTYPE:-}" in
  msys* | cygwin*) candidates+=(py) ;;
  *) ;;
esac

# as_posix <path> -> REPLY: a drive-letter path (C:\x or C:/x) in this shell's POSIX form under Git Bash or Cygwin,
# by string operations alone: cygpath would cost a process start. Any other path is returned as is.
as_posix() {
  REPLY="$1"
  case "${OSTYPE:-}" in
    msys* | cygwin*)
      REPLY="${REPLY//\\//}"
      if [[ "$REPLY" =~ ^([A-Za-z]):(/.*)?$ ]]; then
        REPLY="/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
        [[ "$OSTYPE" == cygwin* ]] && REPLY="/cygdrive$REPLY"
      fi
      ;;
    *) ;;
  esac
}

# path_key <path> -> REPLY: the path as compared. Under Git Bash or Cygwin, paths are case-insensitive and a
# command -v result may drop the .exe that Python's shutil.which keeps.
path_key() {
  as_posix "$1"
  case "${OSTYPE:-}" in
    msys* | cygwin*)
      REPLY="${REPLY,,}"
      REPLY="${REPLY%.exe}"
      ;;
    *) ;;
  esac
}

# stamp_holds -> 0 when pydeps.py's ready stamp (written after a successful install with an interpreter found on
# PATH) still describes this session: the same plugin root, every candidate name resolving where it did, none of
# those files, requirements.txt, pydeps.py or pydeps.json newer than the stamp, and the installed set present.
# Builtins only (hash fills BASH_CMDS the way command -v looks up a name, without a subshell), so a session start
# whose set is ready starts no process. Anything else falls through to the full path, which probes and rebuilds.
stamp_holds() {
  ((BASH_VERSINFO[0] >= 4)) || return 1
  local stamp lines name got want i=3 f
  as_posix "$data"
  stamp="$REPLY/python/.hook-ready"
  [[ -f "$stamp" ]] || return 1
  mapfile -t lines <"$stamp" || return 1
  lines=("${lines[@]%$'\r'}")
  ((${#lines[@]} == 3 + ${#candidates[@]})) && [[ "${lines[0]}" == 'pydeps-hook-ready 1' ]] || return 1
  path_key "${lines[1]}"
  want="$REPLY"
  path_key "$ROOT"
  [[ "$want" == "$REPLY" ]] || return 1
  as_posix "${lines[2]}"
  [[ -d "$REPLY" ]] || return 1
  for name in "${candidates[@]}"; do
    [[ "${lines[i]%%=*}" == "$name" ]] || return 1
    path_key "${lines[i]#*=}"
    want="$REPLY"
    got=""
    hash -- "$name" 2>/dev/null && got="${BASH_CMDS[$name]-}"
    path_key "$got"
    [[ "$want" == "$REPLY" ]] || return 1
    [[ -n "$got" && "$got" -nt "$stamp" ]] && return 1
    i=$((i + 1))
  done
  for f in requirements.txt scripts/pydeps.py scripts/pydeps.json; do
    [[ "$ROOT/$f" -nt "$stamp" ]] && return 1
  done
  return 0
}
stamp_holds && exit 0

py=""
for candidate in "${candidates[@]}"; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  if [[ "$candidate" == py ]]; then
    py="$(launcher_listed)" || py=""
    break
  fi
  [[ "$resolved" == *[Ww]indows[Aa]pps* && ! -s "$resolved" ]] && continue
  "$candidate" -c 'import sys' >/dev/null 2>&1 </dev/null || continue
  py="$candidate"
  break
done

if [[ -z "$py" ]]; then
  notice "$PYDEPS_PLUGIN: Python $PYDEPS_PYTHONS was not found on the hook PATH${candidates[4]:+ or listed by py -0p}; $PYDEPS_USERS will fail. Install one (https://www.python.org/downloads/) and start a new session."
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
  notice "$PYDEPS_PLUGIN: cygpath could not convert its pydeps.py or data directory path to Windows form, so its $PYDEPS_PACKAGES are not installed and $PYDEPS_USERS will stop. Check that cygpath runs in Git Bash and start a new session."
  exit 0
fi

if ! out="$("$py" "$script" install --data-dir "$data_dir" </dev/null 2>&1)"; then
  if [[ "$out" == *Traceback* ]]; then
    last="${out//$'\r'/}"
    last="${last##*$'\n'}"
    notice "$PYDEPS_PLUGIN: the Python handover failed: $last; repair with: $(repair_line)"
  else
    notice "$PYDEPS_PLUGIN: $PYDEPS_PACKAGES not installed; $PYDEPS_USERS will fail. ${out#"$PYDEPS_PLUGIN: "}"
  fi
fi
exit 0
