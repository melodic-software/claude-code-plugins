#!/usr/bin/env bash
# Exit: 0 resolved; 1 not a git repository; 2 usage; 4 the shared extension
# list (code-extensions.txt beside this script) cannot be read, named on stderr.
set -uo pipefail

EXT_LIST="$(dirname "${BASH_SOURCE[0]}")/code-extensions.txt"
EXTS=""
[[ -f "$EXT_LIST" && -r "$EXT_LIST" ]] && EXTS="$(tr -d '\r' <"$EXT_LIST" | grep . | paste -sd'|' -)"
if [[ -z "$EXTS" ]]; then
  printf 'scope-code-files: cannot read the extension list %s\n' "$EXT_LIST" >&2
  exit 4
fi
CODE_EXT="\\.($EXTS)\$"
BASE=""
MAX=""
BRANCH_ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --branch-only)
    BRANCH_ONLY=1
    shift
    ;;
  --base)
    [[ $# -ge 2 ]] || {
      echo "scope-code-files: --base needs a ref" >&2
      exit 2
    }
    BASE="$2"
    shift 2
    ;;
  --max)
    [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || {
      echo "scope-code-files: --max needs a number" >&2
      exit 2
    }
    MAX="$2"
    shift 2
    ;;
  *)
    echo "scope-code-files: unknown argument $1" >&2
    exit 2
    ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 1

nul_lines() { awk 'BEGIN { RS = "\0" } { print }'; }
code_only() { grep -Ei "$CODE_EXT" || true; }
emit() {
  local rung="$1" base="$2" list="$3" n
  n=$(printf '%s' "$list" | grep -c . || true)
  printf 'rung=%s base=%s files=%s\n' "$rung" "${base:-none}" "$n"
  if [[ -n "$list" ]]; then
    if [[ -n "$MAX" ]]; then printf '%s\n' "$list" | head -n "$MAX"; else printf '%s\n' "$list"; fi
  fi
}

resolve_base() {
  local ref
  if [[ -n "$BASE" ]]; then
    git rev-parse --verify -q "$BASE^{commit}" >/dev/null && printf '%s' "$BASE"
    return
  fi
  if ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s' "$ref"
    return 0
  fi
  for ref in origin/main origin/master main master; do
    if git rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1; then
      printf '%s' "$ref"
      return 0
    fi
  done
  return 1
}

if [[ -n "$BRANCH_ONLY" ]]; then
  base=$(resolve_base) || base=""
  if [[ -z "$base" ]]; then
    printf 'scope-code-files: --branch-only needs a base that resolves, got %s\n' "${BASE:-none}" >&2
    exit 2
  fi
  mb=$(git merge-base HEAD "$base" 2>/dev/null) || {
    printf 'scope-code-files: no merge base between HEAD and %s\n' "$base" >&2
    exit 2
  }
  list=$({
    git diff --name-only --diff-filter=ACMR -z "$mb"
    git ls-files --others --exclude-standard --full-name -z -- ':/'
  } | nul_lines | code_only | LC_ALL=C sort -u)
  emit branch "$base" "$list"
  exit 0
fi

if [[ -n "$(git status --porcelain -uall 2>/dev/null)" ]]; then
  list=$(git status --porcelain -uall -z 2>/dev/null |
    awk 'BEGIN { RS = "\0" } skip { skip = 0; next } { if (substr($0, 1, 2) ~ /[RC]/) skip = 1; print substr($0, 4) }' |
    code_only)
  emit uncommitted "" "$list"
  exit 0
fi

base=$(resolve_base) || base=""
if [[ -n "$base" ]]; then
  head=$(git rev-parse HEAD)
  mb=$(git merge-base HEAD "$base" 2>/dev/null || true)
  if [[ -n "$mb" && "$mb" != "$head" ]]; then
    list=$(git diff --name-only --diff-filter=ACMR -z "$mb" HEAD | nul_lines | code_only)
    emit branch "$base" "$list"
    exit 0
  fi
fi

list=$(git ls-files -z | nul_lines | code_only)
emit repository "$base" "$list"
exit 0
