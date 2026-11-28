#!/usr/bin/env bash
# Exit: 0 printed (possibly nothing); 2 usage.
set -uo pipefail
shopt -s nullglob

HERE="${BASH_SOURCE[0]%/*}"
[[ "$HERE" == "${BASH_SOURCE[0]}" ]] && HERE=.
HERE="$(cd "$HERE" && pwd)" || exit 2

usage() {
  printf 'usage: transcript_dirs.sh --scope <worktree|repo|all> [--sources-file F]\n  F: the transcript_sources_file option; its local sources are the stores (default: this host)\n' >&2
  exit 2
}
ARGV=("$@")
SCOPE=""
SOURCES_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --scope) [[ $# -ge 2 && -z "$SCOPE" ]] || usage; SCOPE="$2"; shift 2 ;;
  --sources-file) [[ $# -ge 2 ]] || usage; SOURCES_FILE="$2"; shift 2 ;;
  *) usage ;;
  esac
done
case "$SCOPE" in worktree | repo | all) ;; *) usage ;; esac

win_form() {
  local out
  if command -v cygpath >/dev/null 2>&1 && out="$(cygpath -w "$1" 2>/dev/null)"; then
    printf '%s' "$out"
  else
    printf '%s' "$1"
  fi
}

roots=()
if [[ "$SCOPE" != all ]]; then
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
fi

source "$HERE/../lib/python-probe.sh"
PY=""
python_probe::floor_interpreter_to PY

STORES=()
if [[ -n "$PY" ]]; then
  # shellcheck disable=SC2016 # the program is literal Python
  listed="$("$PY" -I -X utf8 -c 'import sys
sys.path.insert(0, sys.argv[1])
import transcript_sources as t
try:
    report = t.lookup_report(sys.argv[2], t.retry_argv(sys.argv[3], sys.argv[4:], interpreter="bash"))
except t.SourcesError as error:
    print(f"transcript_dirs: {error}", file=sys.stderr)
    sys.exit(2)
for line in report.header:
    print(line, file=sys.stderr)
for entry in report.sources.local():
    print(entry.config_dir)' "$HERE" "$SOURCES_FILE" "$HERE/transcript_dirs.sh" "${ARGV[@]}")" || exit 2
  while IFS= read -r config; do
    [[ -n "$config" ]] && STORES+=("$config/projects")
  done <<<"$listed"
elif [[ -n "$SOURCES_FILE" ]]; then
  printf 'gap: Python 3.10+ not found, so the sources file was not read and no directory was listed\n' >&2
  exit 0
else
  config="${CLAUDE_CONFIG_DIR:-}"
  [[ -n "$config" ]] || config="$HOME/.claude"
  STORES=("$config/projects")
fi

if [[ -n "$PY" && -f "$HERE/../lib/claude_projects.py" ]]; then
  root_args=()
  for root in ${roots[@]+"${roots[@]}"}; do
    root_args+=(--root "$root")
  done
  for STORE in ${STORES[@]+"${STORES[@]}"}; do
    "$PY" -I -X utf8 "$HERE/../lib/claude_projects.py" resolve-project-dirs --scope "$SCOPE" \
      --projects-dir "$STORE" ${root_args[@]+"${root_args[@]}"} || exit 2
  done
  exit 0
fi

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
    for STORE in ${STORES[@]+"${STORES[@]}"}; do
      [[ -d "$STORE/$pinned" ]] && emit "$STORE/$pinned"
    done
    exit 0
    ;;
  esac
fi

if [[ "$SCOPE" == all ]]; then
  for STORE in ${STORES[@]+"${STORES[@]}"}; do
    for dir in "$STORE"/*/; do emit "${dir%/}"; done
  done
  exit 0
fi

encode() {
  local LC_ALL=C s="$1"
  s="${s//[$'\x80'-$'\xbf']/}"
  s="${s//[$'\xf0'-$'\xf7']/--}"
  printf '%s' "${s//[^A-Za-z0-9]/-}"
}

SKIPPED=0
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
      SKIPPED=1
    fi
  done
}

for STORE in ${STORES[@]+"${STORES[@]}"}; do
  for root in "${roots[@]}"; do scan_root "$root"; done
done

if [[ "$SKIPPED" -eq 1 ]]; then
  printf 'gap: Python 3.10+ not found; only exact-name directories were listed, so sessions started in a subdirectory or under a hashed long name were skipped\n' >&2
fi
exit 0
