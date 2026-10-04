#!/usr/bin/env bash
# Print the Claude Code transcript directories one scope covers, one per line.
#
#   transcript_dirs.sh --scope worktree   this worktree's project directories
#   transcript_dirs.sh --scope repo       every worktree of this repository, this one first
#   transcript_dirs.sh --scope all        every directory in the transcript store
#
# The store is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects. A directory's name
# is the session's working directory with every character that is not a letter
# or digit replaced by `-`; past 200 characters the name keeps its first 200
# and gains a hash. CLAUDE_CODE_PROJECT_DIR_NAME, honoured only when
# CLAUDE_CONFIG_DIR is set too, pins one name for every session.
# Pointer: https://code.claude.com/docs/en/sessions#where-transcripts-are-stored
# and #name-the-project-directory-yourself. As of 2026-10-04. Recheck when that
# page changes the naming rule, the 200-character limit, or either variable.
#
# A root is a worktree's top level (outside a repository, the current
# directory), in Windows form through `cygpath -w` where cygpath exists. For
# each root, a directory whose name equals the encoded root is kept. A name that
# extends it (`<encoded>-...`, a session started in a subdirectory or a sibling
# whose path shares the prefix) or, for a root encoded to 200 or more
# characters, shares its first 200, is kept only when the `cwd` recorded in its
# newest transcript is the root or lies under it. That `cwd` is the only
# transcript content read, through transcript_reader.first_cwd. Without Python
# 3.10+ those candidates are skipped and stderr carries one `gap:` line.
#
# Directory names are data: printed as they are, never evaluated.
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
  local LC_ALL=C
  printf '%s' "${1//[^A-Za-z0-9]/-}"
}

# Forward slashes and a lower-case drive letter.
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

# confirm <root> <dir>: the newest transcript in <dir> records a cwd at or under <root>.
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
  cwd="$("$PY" -X utf8 -c 'import sys
sys.path.insert(0, sys.argv[1])
import transcript_reader
sys.stdout.write(transcript_reader.first_cwd(sys.argv[2]) or "")' "$HERE" "$newest" 2>/dev/null)" || return 1
  [[ -n "$cwd" ]] || return 1
  cwd="$(norm "$cwd")"
  root="$(norm "$root")"
  [[ "$cwd" == "$root" || "$cwd" == "$root/"* ]]
}

scan_root() {
  local root="$1" enc long="" dir name
  enc="$(encode "$root")"
  [[ -n "$enc" ]] || return 0
  [[ -d "$STORE/$enc" ]] && emit "$STORE/$enc"
  [[ "${#enc}" -ge 200 ]] && long="${enc:0:200}"
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
