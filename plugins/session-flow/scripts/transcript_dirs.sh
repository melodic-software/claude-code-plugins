#!/usr/bin/env bash
# Exit: 0 printed (possibly nothing); 2 usage.
set -uo pipefail
shopt -s nullglob

HERE="${BASH_SOURCE[0]%/*}"
[[ "$HERE" == "${BASH_SOURCE[0]}" ]] && HERE=.
HERE="$(cd "$HERE" && pwd)" || exit 2

usage() {
  printf 'usage: transcript_dirs.sh --scope <worktree|repo|all>\n' >&2
  exit 2
}
[[ $# -eq 2 && "$1" == --scope ]] || usage
SCOPE="$2"
case "$SCOPE" in worktree | repo | all) ;; *) usage ;; esac

STORE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"

PRINTED=()
emit() {
  local seen
  for seen in ${PRINTED[@]+"${PRINTED[@]}"}; do
    [[ "$seen" == "$1" ]] && return 0
  done
  PRINTED+=("$1")
  printf '%s\n' "$1"
}

pinned="${CLAUDE_CODE_PROJECT_DIR_NAME:-}"
if [[ -n "${CLAUDE_CONFIG_DIR:-}" && "$pinned" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
  case "$(printf '%s' "$pinned" | tr '[:upper:]' '[:lower:]')" in
  con | prn | aux | nul | com[0-9] | lpt[0-9]) ;;
  *)
    [[ -d "$STORE/$pinned" ]] && emit "$STORE/$pinned"
    exit 0
    ;;
  esac
fi

if [[ "$SCOPE" == all ]]; then
  for dir in "$STORE"/*/; do emit "${dir%/}"; done
  exit 0
fi

win_form() {
  local out
  if command -v cygpath >/dev/null 2>&1 && out="$(cygpath -w "$1" 2>/dev/null)"; then
    printf '%s' "$out"
  else
    printf '%s' "$1"
  fi
}

encode() {
  local LC_ALL=C s="$1"
  s="${s//[$'\x80'-$'\xbf']/}"
  s="${s//[$'\xf0'-$'\xf7']/--}"
  printf '%s' "${s//[^A-Za-z0-9]/-}"
}

norm() {
  local p="${1//\\//}" drive
  if [[ "$p" =~ ^([A-Za-z]):(.*)$ ]]; then
    drive="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    p="$drive:${BASH_REMATCH[2]}"
  fi
  printf '%s' "$p"
}

source "$HERE/../lib/python-probe.sh"
PY=""
python_probe::floor_interpreter_to PY
SKIPPED=0

confirm() {
  local root="$1" dir="$2" newest="" f cwd
  if [[ -z "$PY" ]]; then
    SKIPPED=1
    return 1
  fi
  for f in "$dir"/*.jsonl; do
    [[ -f "$f" ]] || continue
    if [[ -z "$newest" || "$f" -nt "$newest" ]]; then newest="$f"; fi
  done
  [[ -n "$newest" ]] || return 1
  cwd="$("$PY" -I -X utf8 -c 'import sys
sys.path.insert(0, sys.argv[1])
import transcript_reader
sys.stdout.write(transcript_reader.first_cwd(sys.argv[2]) or "")' "$HERE" "$newest" 2>/dev/null)" || return 1
  [[ -n "$cwd" ]] || return 1
  cwd="$(norm "$cwd")"
  [[ "$cwd" == "$root" || "$cwd" == "$root/"* ]]
}

scan_root() {
  local root="$1" enc long="" dir name
  enc="$(encode "$root")"
  [[ -n "$enc" ]] || return 0
  [[ -d "$STORE/$enc" ]] && emit "$STORE/$enc"
  [[ "${#enc}" -ge 200 ]] && long="${enc:0:200}"
  root="$(norm "$root")"
  for dir in "$STORE"/*/; do
    dir="${dir%/}"
    name="${dir##*/}"
    [[ "$name" == "$enc" ]] && continue
    if [[ "$name" == "$enc-"* || (-n "$long" && "$name" == "$long"*) ]]; then
      confirm "$root" "$dir" && emit "$dir"
    fi
  done
}

here_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
in_repo=1
if [[ -z "$here_root" ]]; then
  in_repo=0
  here_root="$(pwd)"
fi
here_root="$(win_form "$here_root")"
roots=("$here_root")

if [[ "$SCOPE" == repo && "$in_repo" -eq 1 ]]; then
  while IFS= read -r line; do
    [[ "$line" == "worktree "* ]] && roots+=("$(win_form "${line#worktree }")")
  done < <(git worktree list --porcelain 2>/dev/null | tr -d '\r')
fi

for root in "${roots[@]}"; do scan_root "$root"; done

if [[ "$SKIPPED" -eq 1 ]]; then
  printf 'gap: Python 3.10+ not found; only exact-name directories were listed, so sessions started in a subdirectory or under a hashed long name were skipped\n' >&2
fi
exit 0
