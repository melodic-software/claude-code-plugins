#!/usr/bin/env bash
set -uo pipefail

data="${CLAUDE_PLUGIN_DATA:-}"
[[ -n "$data" ]] || exit 0

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ROOT="${SCRIPT_DIR%/*}"

PYDEPS_PLUGIN="install-python-deps" PYDEPS_PYTHONS="3.12 or later" PYDEPS_USERS="its skills" PYDEPS_PACKAGES="Python packages"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/install-python-deps.conf"

notice() {
  # shellcheck source=hook-utils.sh
  source "$SCRIPT_DIR/hook-utils.sh"
  hook::emit_skip_notice SessionStart "" "$1"
}

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

candidates=(python3.13 python3.12 python3 python)
case "${OSTYPE:-}" in
  msys* | cygwin*) candidates+=(py) ;;
  *) ;;
esac

as_posix() {
  REPLY="$1"
  case "${OSTYPE:-}" in
    msys* | cygwin*)
      REPLY="${REPLY//\\//}"
      if [[ "$REPLY" =~ ^([A-Za-z]):(/.*)?$ ]]; then
        local drive="${BASH_REMATCH[1],,}" rest="${BASH_REMATCH[2]}"
        if [[ -d "/$drive" ]]; then
          REPLY="/$drive$rest"
        elif [[ -d "/cygdrive/$drive" ]]; then
          REPLY="/cygdrive/$drive$rest"
        else
          return 1
        fi
      fi
      ;;
    *) ;;
  esac
}

stamp_holds() {
  ((BASH_VERSINFO[0] >= 4)) || return 1
  local stamp lines name got i=3 f
  as_posix "$data" || return 1
  stamp="$REPLY/python/.hook-ready"
  [[ -f "$stamp" ]] || return 1
  mapfile -t lines <"$stamp" || return 1
  lines=("${lines[@]%$'\r'}")
  ((${#lines[@]} == 3 + ${#candidates[@]})) && [[ "${lines[0]}" == 'pydeps-hook-ready 1' ]] || return 1
  as_posix "${lines[1]}" || return 1
  [[ "$REPLY/scripts/pydeps.py" -ef "$ROOT/scripts/pydeps.py" ]] || return 1
  as_posix "${lines[2]}" || return 1
  [[ -d "$REPLY" ]] || return 1
  for name in "${candidates[@]}"; do
    [[ "${lines[i]%%=*}" == "$name" ]] || return 1
    as_posix "${lines[i]#*=}" || return 1
    got=""
    hash -- "$name" 2>/dev/null && got="${BASH_CMDS[$name]-}"
    if [[ -n "$REPLY" || -n "$got" ]]; then
      [[ -n "$REPLY" && -n "$got" && "$REPLY" -ef "$got" ]] || return 1
      [[ "$got" -nt "$stamp" ]] && return 1
    fi
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
