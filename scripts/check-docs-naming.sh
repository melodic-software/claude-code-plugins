#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SRC="${BASH_SOURCE[0]}"
[[ "$SCRIPT_SRC" == */* ]] || SCRIPT_SRC="./$SCRIPT_SRC"
SCRIPT_DIR="$(cd "${SCRIPT_SRC%/*}" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if ! command -v git >/dev/null 2>&1; then
  printf 'check-docs-naming: git is required to list the tracked files in scope\n' >&2
  exit 2
fi
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  printf 'check-docs-naming: not inside a git repository, nothing inspected\n' >&2
  exit 2
fi

PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  printf 'check-docs-naming: python 3 is required to fold paths for the case-collision check\n' >&2
  exit 2
fi
FOLD_PY='import sys
data = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
sys.stdout.buffer.write(data.lower().encode("utf-8", "surrogateescape"))'

NAME_RE='^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$'
EXEMPT_NAMES=' README.md CHANGELOG.md INDEX.md LICENSE.md AGENTS.md CLAUDE.md SKILL.md CONTRIBUTING.md SECURITY.md REVIEW.md CODE_OF_CONDUCT.md CONTRACT.md STYLE.md TODO.md PLAN.md '
offenders=()

paths=()
while IFS= read -r -d '' path; do
  paths+=("$path")
done < <(git ls-files -z -- docs/ ':(icase)*.md')

for path in ${paths+"${paths[@]}"}; do
  base="${path##*/}"
  if [[ "$path" == docs/* ]]; then
    case "${base##*.}" in
    py | sh | mjs | js | ps1) continue ;;
    *) ;;
    esac
  else
    case "/$path" in
    */fixtures/* | */evals/* | */vendor/*) continue ;;
    *) ;;
    esac
  fi
  [[ "$EXEMPT_NAMES" == *" $base "* ]] && continue
  if [[ ! "$base" =~ $NAME_RE ]]; then
    offenders+=("$path: basename is not lower-kebab-case (rule: $NAME_RE)")
  fi
done

folded=()
dups=""
if ((${#paths[@]} > 0)); then
  while IFS= read -r -d '' one; do
    folded+=("$one")
  done < <(printf '%s\0' "${paths[@]}" | "$PYTHON" -c "$FOLD_PY")
  dups="$(printf '%q\n' ${folded+"${folded[@]}"} | sort | uniq -d)"
fi

if [[ -n "$dups" ]]; then
  for ((i = 0; i < ${#paths[@]}; i++)); do
    one="${folded[$i]}"
    if [[ -n "$one" ]]; then
      printf -v key '%q' "$one"
      if [[ $'\n'"$dups"$'\n' == *$'\n'"$key"$'\n'* ]]; then
        shown="${paths[$i]}"
        [[ "$one" == *$'\n'* ]] && printf -v shown '%q' "$shown" && one="$key"
        offenders+=("$shown: differs only by case from another tracked path ($one)")
      fi
    fi
  done
fi

if ((${#offenders[@]} == 0)); then
  printf 'check-docs-naming: every tracked file under docs/ is lower-kebab-case, and so is every tracked .md file outside it.\n'
  exit 0
fi

printf '%s\n' "${offenders[@]}" | sort -u >&2
printf 'check-docs-naming: %d offender(s); rename to lower-kebab-case (see the header of %s).\n' \
  "${#offenders[@]}" "scripts/${0##*/}" >&2
exit 1
