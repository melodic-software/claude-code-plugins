#!/usr/bin/env bash
# Classify files into the plugin's lanes (design thread T2).
#
#   detect-lanes.sh [--globs <lane>=<glob>[,<glob>...]]... [--disable <lane>]...
#                   [--paths-from <file>] [--] <file>...
#
# `--paths-from` reads the file list from a file, one path per line. A scope of
# tens of thousands of paths does not fit in one argument vector on every
# platform this runs on, and the file has no such ceiling.
#
# Prints one `<lane><TAB><file>` line per file that belongs to a lane, in the
# order the files were given; a file that belongs to no lane prints nothing.
# The bundled map classifies by extension. `--globs` replaces the bundled map
# for that lane with gitignore-style globs (the consumer's ecosystem file
# `globs`, resolved by the caller), matched through pathglob.py. `--disable`
# drops a lane entirely (a resolved `enabled: false`).
#
# Exit: 0 classified (an empty result is still 0); 2 usage or environment error.
set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PATHGLOB="$SCRIPT_DIR/pathglob.py"

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

# shellcheck source=python-resolve.sh
source "$SCRIPT_DIR/python-resolve.sh"

# Bundled extension map. Lower-cased extension -> lane.
lane_for_extension() {
  case "$1" in
  ts | tsx | mts | cts | js | jsx | mjs | cjs) printf 'typescript\n' ;;
  py | pyi) printf 'python\n' ;;
  sh | bash) printf 'bash\n' ;;
  go) printf 'go\n' ;;
  cs) printf 'dotnet\n' ;;
  *) printf '\n' ;;
  esac
}

declare -A LANE_GLOBS=()
declare -A DISABLED=()
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --globs)
    [[ $# -ge 2 && "$2" == *=* ]] || {
      usage
      exit 2
    }
    LANE_GLOBS["${2%%=*}"]="${2#*=}"
    shift 2
    ;;
  --disable)
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    DISABLED["$2"]=1
    shift 2
    ;;
  --paths-from)
    # The whole scope can be tens of thousands of paths, and passing it as one
    # argument vector fails outright once it crosses the platform's command
    # line limit, which on Git Bash under Windows is far smaller than on
    # Linux. A file has no such ceiling.
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    [[ -f "$2" ]] || {
      printf 'detect-lanes.sh: path list does not exist: %s\n' "$2" >&2
      exit 2
    }
    while IFS= read -r listed; do
      [[ -n "$listed" ]] && FILES+=("$listed")
    done <"$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  --)
    shift
    FILES+=("$@")
    break
    ;;
  -*)
    usage
    exit 2
    ;;
  *)
    FILES+=("$1")
    shift
    ;;
  esac
done

[[ ${#FILES[@]} -gt 0 ]] || exit 0

PY=()
if [[ ${#LANE_GLOBS[@]} -gt 0 ]]; then
  set +e
  cm_resolve_python
  resolved_rc=$?
  set -e
  if [[ $resolved_rc -ne 0 ]]; then
    echo "detect-lanes.sh: Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); needed for --globs matching" >&2
    exit 2
  fi
fi

# Glob-driven lanes are decided first, one pathglob call per pattern, so a
# consumer override wins over the extension map for its lane.
declare -A GLOB_LANE_OF=()
GLOB_HITS="$(mktemp)"
FILE_LIST="$(mktemp)"
trap 'rm -f "$GLOB_HITS" "$FILE_LIST"' EXIT
# The matcher reads the scope from a file for the same reason this script
# accepts one: a whole repository's paths do not fit in one argument vector on
# every platform this runs on.
printf '%s\n' "${FILES[@]}" >"$FILE_LIST"
for lane in "${!LANE_GLOBS[@]}"; do
  IFS=',' read -r -a patterns <<<"${LANE_GLOBS[$lane]}"
  for pattern in "${patterns[@]}"; do
    [[ -n "$pattern" ]] || continue
    # The matcher's output goes to a file and its exit status is checked before
    # the file is read: a process substitution reports only the read's own
    # success, so a pattern the matcher refused would read as "matched
    # nothing". Declaring globs turns off this lane's extension fallback, so
    # that silence would drop the lane's files from the run entirely.
    if ! "${PY[@]}" "$PATHGLOB" "$pattern" --paths-from "$FILE_LIST" >"$GLOB_HITS"; then
      printf 'detect-lanes.sh: lane %s: the glob %s could not be used (see the message above)\n' \
        "$lane" "$pattern" >&2
      exit 2
    fi
    while IFS= read -r hit; do
      [[ -n "$hit" ]] && GLOB_LANE_OF["$hit"]="$lane"
    done <"$GLOB_HITS"
  done
done

for file in "${FILES[@]}"; do
  normalized="${file//\\//}"
  lane=""
  if [[ -n "${GLOB_LANE_OF[$file]:-}" ]]; then
    lane="${GLOB_LANE_OF[$file]}"
  else
    base="${normalized##*/}"
    ext=""
    [[ "$base" == *.* ]] && ext="$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')"
    lane="$(lane_for_extension "$ext")"
    # A lane the consumer redefined by globs no longer claims files by extension.
    [[ -n "$lane" && -n "${LANE_GLOBS[$lane]:-}" ]] && lane=""
  fi
  [[ -n "$lane" ]] || continue
  [[ -n "${DISABLED[$lane]:-}" ]] && continue
  printf '%s\t%s\n' "$lane" "$normalized"
done
