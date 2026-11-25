#!/usr/bin/env bash
CM_USAGE=$(cat <<'EOF'
Classify files into the plugin's languages (design thread T2).

  detect-languages.sh [--globs <language>=<glob>[,<glob>...]]... [--disable <language>]...
                  [--paths-from <file>] [--] <file>...

`--paths-from` reads the file list from a file, one path per line. A scope of
tens of thousands of paths does not fit in one argument vector on every
platform this runs on, and the file has no such ceiling.

Prints one `<language><TAB><file>` line per file, in the order the files were
given. The bundled map classifies by extension into the languages; a
file whose extension no language claims lands in the catch-all `other`
EOF
)
set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PATHGLOB="$SCRIPT_DIR/pathglob.py"

usage() {
  cm_usage_banner --usage "$CM_USAGE"
}

# shellcheck source=python-resolve.sh
source "$SCRIPT_DIR/python-resolve.sh"
# shellcheck source=entry-common.sh
source "$SCRIPT_DIR/entry-common.sh"

language_for_extension() {
  case "$1" in
  ts | tsx | mts | cts | js | jsx | mjs | cjs) LANGUAGE=typescript ;;
  py | pyi) LANGUAGE=python ;;
  sh | bash) LANGUAGE=bash ;;
  go) LANGUAGE=go ;;
  cs) LANGUAGE=dotnet ;;
  *) LANGUAGE=other ;;
  esac
}

declare -A LANGUAGE_GLOBS=()
declare -A DISABLED=()
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --globs)
    [[ $# -ge 2 && "$2" == *=* ]] || {
      usage
      exit 2
    }
    LANGUAGE_GLOBS["${2%%=*}"]="${2#*=}"
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
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    [[ -f "$2" ]] || {
      printf 'detect-languages.sh: path list does not exist: %s\n' "$2" >&2
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
if [[ ${#LANGUAGE_GLOBS[@]} -gt 0 ]]; then
  set +e
  cm_resolve_python
  resolved_rc=$?
  set -e
  if [[ $resolved_rc -ne 0 ]]; then
    echo "detect-languages.sh: Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); needed for --globs matching" >&2
    exit 2
  fi
fi

declare -A GLOB_LANGUAGE_OF=()
GLOB_HITS="$(mktemp)"
FILE_LIST="$(mktemp)"
trap 'rm -f "$GLOB_HITS" "$FILE_LIST"' EXIT
printf '%s\n' "${FILES[@]}" >"$FILE_LIST"
for language in "${!LANGUAGE_GLOBS[@]}"; do
  IFS=',' read -r -a patterns <<<"${LANGUAGE_GLOBS[$language]}"
  for pattern in "${patterns[@]}"; do
    [[ -n "$pattern" ]] || continue
    if ! "${PY[@]}" "$PATHGLOB" "$pattern" --paths-from "$FILE_LIST" >"$GLOB_HITS"; then
      printf 'detect-languages.sh: language %s: the glob %s could not be used (see the message above)\n' \
        "$language" "$pattern" >&2
      exit 2
    fi
    while IFS= read -r hit; do
      [[ -n "$hit" ]] && GLOB_LANGUAGE_OF["$hit"]="$language"
    done <"$GLOB_HITS"
  done
done

for file in "${FILES[@]}"; do
  normalized="${file//\\//}"
  if [[ -n "${GLOB_LANGUAGE_OF[$file]:-}" ]]; then
    language="${GLOB_LANGUAGE_OF[$file]}"
  else
    base="${normalized##*/}"
    ext=""
    if [[ "$base" == *.* ]]; then
      ext="${base##*.}"
      ext="${ext,,}"
    fi
    language_for_extension "$ext"
    language="$LANGUAGE"
    [[ -n "${LANGUAGE_GLOBS[$language]:-}" ]] && language=""
  fi
  [[ -n "$language" ]] || continue
  [[ -n "${DISABLED[$language]:-}" ]] && continue
  printf '%s\t%s\n' "$language" "$normalized"
done
