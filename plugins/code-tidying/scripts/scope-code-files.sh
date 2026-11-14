#!/usr/bin/env bash
# scope-code-files.sh — resolve remove-comments' empty-argument scope ladder.
#
# The ladder advances on ABSENCE of a rung, never on emptiness of one:
#   uncommitted   the working tree has changes (any path); lists their code files
#   branch        clean tree, and HEAD carries commits the base branch lacks;
#                 lists the code files changed since the merge-base
#   repository    clean tree on the base branch (or no base resolvable while
#                 clean); lists every tracked code file
# A rung that exists but yields zero code files is reported with zero files,
# so a docs-only branch never silently widens to the whole repository.
#
# Base branch: --base <ref>, else refs/remotes/origin/HEAD, else origin/main,
# origin/master, main, master, in that order.
#
# Usage: scope-code-files.sh [--base <ref>] [--max <n>]
# Output: line 1 `rung=<name> base=<ref-or-none> files=<count>`, then one
#         repo-relative path per line (capped at --max when given).
# Exit: 0 resolved; 1 not a git repository; 2 usage; 4 the shared extension
# list (code-extensions.txt beside this script) cannot be read, named on stderr.
set -uo pipefail

# The extension list is shared with changed-code-files.sh and comment-census.py,
# and must cover every file the change-shape and commented-out-code grammars accept.
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
while [[ $# -gt 0 ]]; do
  case "$1" in
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

# Rung 1: uncommitted; rename/copy entries emit the new path only. The -z stream is
# piped straight into awk, since a command substitution drops NULs and folds every
# record into one. -uall lists files inside a new directory, not `?? dir/`.
if [[ -n "$(git status --porcelain -uall 2>/dev/null)" ]]; then
  list=$(git status --porcelain -uall -z 2>/dev/null |
    awk 'BEGIN { RS = "\0" } skip { skip = 0; next } { if (substr($0, 1, 2) ~ /[RC]/) skip = 1; print substr($0, 4) }' |
    code_only)
  emit uncommitted "" "$list"
  exit 0
fi

# Rung 2: branch diff against the base's merge-base.
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

# Rung 3: whole repository.
list=$(git ls-files -z | nul_lines | code_only)
emit repository "$base" "$list"
exit 0
