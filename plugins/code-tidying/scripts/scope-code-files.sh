#!/usr/bin/env bash
# scope-code-files.sh — resolve dissolve-comments' empty-argument scope ladder.
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
# Exit: 0 resolved; 1 not a git repository; 2 usage.
set -uo pipefail

# Keep in step with CODE_EXT in comment-census.py: the census must count every
# file this resolver lists, and this resolver must list every file the
# change-shape and commented-out-code grammars accept.
CODE_EXT='\.(cs|ts|tsx|mts|cts|js|jsx|mjs|cjs|py|pyi|sh|bash|ps1|psm1|go|rs|java|rb|lua|sql|c|h|cpp|hpp|yaml|yml|toml)$'
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
    git rev-parse --verify -q "$BASE^{commit}" >/dev/null && {
      printf '%s' "$BASE"
      return 0
    }
    return 1
  fi
  ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) && {
    printf '%s' "$ref"
    return 0
  }
  for ref in origin/main origin/master main master; do
    git rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1 && {
      printf '%s' "$ref"
      return 0
    }
  done
  return 1
}

# Rung 1: uncommitted. Rename/copy entries emit the new path only. The -z
# stream is piped straight into awk: a command substitution drops NUL bytes,
# which would fold every record into one and list a single path. -uall lists
# the files inside a new directory; the default collapses them to `?? dir/`,
# which no extension matches.
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
