#!/usr/bin/env bash
# Shared helpers for git-hook check scripts: the file set, the changed lines,
# the push range, the missing-tool skip key and agent detection. A check script
# sources this file from its own directory and runs under bash, never under sh.
# The contract is the check-placement convention's check-script runtime table.
#
# Names are POSIX-safe (checks_files, not checks::files) and the syntax stays
# within bash 3.2, which is what macOS ships: no associative arrays, no
# mapfile, no ${var,,}. Every git call that can legitimately fail (an unset
# config key, a missing ref) is guarded, so the helpers also hold under set -e.
#
#   checks_init <event> "$@"   set CHECKS_MODE (pre-commit, pre-push or, with
#                              --worktree, worktree), CHECKS_EVENT, CHECKS_TMP,
#                              and cd to the top level; returns 1 outside a repo
#   checks_files               NUL-separated paths to check, repo-relative
#   checks_changed_lines       write "<path><TAB><start><TAB><end>" ranges of
#                              added lines to $CHECKS_TMP/ranges
#   checks_filter_findings     stdin "<path>:<line>: <message>" lines; prints
#                              those inside a changed range
#   checks_partly_staged <p>   0 when <p> has unstaged changes too
#   checks_require_tool <tool> <install>
#                              returns 0 when the tool is on PATH, else exits
#                              the script with the contract's missing-tool rule
#   checks_is_agent            0 when an agent runs the hook
#   checks_skip_listed <tool>  0 when checks.skipmissing names the tool
#   checks_push_ranges         pre-push: "<base> <local>" per pushed ref

CHECKS_EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904

checks_init() {
  CHECKS_EVENT="$1"
  shift
  CHECKS_MODE="$CHECKS_EVENT"
  CHECKS_ARGS=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --worktree) CHECKS_MODE=worktree ;;
    *) CHECKS_ARGS="${CHECKS_ARGS:+$CHECKS_ARGS }$1" ;;
    esac
    shift
  done
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  cd "$top" || return 1
  CHECKS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/checks.XXXXXX")" || return 1
  # shellcheck disable=SC2064 # expand now: the path is fixed at init
  trap "rm -rf '$CHECKS_TMP'" EXIT
  if [[ "$CHECKS_MODE" == pre-push ]]; then
    checks_push_ranges >"$CHECKS_TMP/push-ranges"
  fi
  return 0
}

checks_is_agent() {
  [[ "${CLAUDECODE:-}" == 1 || -n "${AI_AGENT:-}" ]]
}

# git config --get exits 1 for an unset key; that is an empty list, not an error.
checks_skip_listed() {
  local list item
  list="$(git config --get checks.skipmissing 2>/dev/null || true)"
  [[ -n "$list" ]] || return 1
  local IFS=,
  for item in $list; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ "$item" == "$1" ]] && return 0
  done
  return 1
}

checks_git_verb() {
  case "$CHECKS_EVENT" in
  pre-push) printf 'push' ;;
  *) printf 'commit' ;;
  esac
}

checks_require_tool() {
  local tool="$1" install="$2" verb
  command -v "$tool" >/dev/null 2>&1 && return 0
  if checks_skip_listed "$tool"; then
    printf 'SKIPPED: %s (missing)\n' "$tool" >&2
    exit 0
  fi
  verb="$(checks_git_verb)"
  if checks_is_agent; then
    printf 'FAIL: %s missing. Install: %s\n' "$tool" "$install" >&2
    printf 'To skip only while %s is missing: git -c checks.skipmissing=%s %s ...\n' "$tool" "$tool" "$verb" >&2
    exit 1
  fi
  printf 'NOTICE: %s missing, so this check did not run. Install: %s\n' "$tool" "$install" >&2
  exit 0
}

# The default branch of <remote>: <remote>/HEAD when it resolves, else the
# remote's own symref from ls-remote when that branch is fetched here. Prints
# nothing when neither resolves.
checks_remote_head() {
  local remote="$1" ref line
  ref="$(git rev-parse --verify --quiet "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  if [[ -n "$ref" ]]; then
    printf '%s' "$ref"
    return 0
  fi
  line="$(git ls-remote --symref "$remote" HEAD 2>/dev/null | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' || true)"
  [[ -n "$line" ]] || return 0
  git rev-parse --verify --quiet "refs/remotes/$remote/$line" 2>/dev/null || true
}

# Reads git's pre-push stdin. A deletion (all-zero local sha) is skipped; a new
# branch (all-zero remote sha) starts at its merge-base with the remote's
# default branch, and is skipped with a notice when that cannot be found. With
# no stdin at all (a hook manager that kept it from this script), the current
# branch against its upstream is the range.
checks_push_ranges() {
  local remote="${CHECKS_ARGS%% *}" zero=0000000000000000000000000000000000000000
  local lref lsha rsha head base seen=0
  [[ -n "$remote" ]] || remote=origin
  while read -r lref lsha _ rsha; do
    [[ -n "$lsha" ]] || continue
    seen=1
    [[ "$lsha" == "$zero" ]] && continue
    if [[ "$rsha" != "$zero" ]]; then
      printf '%s %s\n' "$rsha" "$lsha"
      continue
    fi
    head="$(checks_remote_head "$remote")"
    base=""
    [[ -z "$head" ]] || base="$(git merge-base "$lsha" "$head" 2>/dev/null || true)"
    if [[ -z "$base" ]]; then
      printf 'NOTICE: no default branch found for %s, so %s was not checked.\n' "$remote" "$lref" >&2
      continue
    fi
    printf '%s %s\n' "$base" "$lsha"
  done
  ((seen)) && return 0
  base="$(git rev-parse --verify --quiet '@{upstream}' 2>/dev/null || true)"
  [[ -n "$base" ]] && printf '%s %s\n' "$base" "$(git rev-parse HEAD)"
  return 0
}

# checks_diff <git diff options...>: the diff for the current mode.
# core.quotePath=false keeps non-ASCII names unquoted.
checks_diff() {
  case "$CHECKS_MODE" in
  pre-commit) git -c core.quotePath=false diff --cached --no-color --no-ext-diff "$@" ;;
  worktree)
    local base=HEAD
    git rev-parse --verify --quiet HEAD >/dev/null 2>&1 || base="$CHECKS_EMPTY_TREE"
    git -c core.quotePath=false diff "$base" --no-color --no-ext-diff "$@"
    ;;
  pre-push)
    local b l
    while read -r b l; do
      git -c core.quotePath=false diff "$b" "$l" --no-color --no-ext-diff "$@"
    done <"$CHECKS_TMP/push-ranges"
    ;;
  *) return 1 ;;
  esac
}

checks_files() {
  checks_diff --name-only --diff-filter=ACMR -z
  if [[ "$CHECKS_MODE" == worktree ]]; then
    git ls-files --others --exclude-standard -z
  fi
}

# Hunk headers read "@@ -a[,b] +c[,d] @@"; d defaults to 1 and d=0 adds
# nothing. Paths come from "+++ b/<path>", where git appends a tab to a name
# holding a space; a name git still quotes is skipped.
checks_changed_lines() {
  local out="$CHECKS_TMP/ranges"
  : >"$out"
  checks_diff -U0 --diff-filter=ACMR --src-prefix=a/ --dst-prefix=b/ 2>/dev/null |
    awk '
      /^\+\+\+ / { path = substr($0, 5); sub(/\t$/, "", path); if (path ~ /^b\//) path = substr(path, 3); else path = ""; next }
      /^@@ / && path != "" {
        split($3, n, ",")
        start = substr(n[1], 2) + 0
        count = (n[2] == "") ? 1 : n[2] + 0
        if (count > 0) printf "%s\t%d\t%d\n", path, start, start + count - 1
      }' >>"$out"
  if [[ "$CHECKS_MODE" == worktree ]]; then
    local f
    while IFS= read -r -d '' f; do
      printf '%s\t1\t2147483647\n' "$f" >>"$out"
    done < <(git ls-files --others --exclude-standard -z)
  fi
}

checks_filter_findings() {
  awk -v ranges="$CHECKS_TMP/ranges" '
    BEGIN { while ((getline l < ranges) > 0) { split(l, r, "\t"); n++; p[n] = r[1]; s[n] = r[2] + 0; e[n] = r[3] + 0 } }
    {
      if (!match($0, /:[0-9]+: /)) next
      path = substr($0, 1, RSTART - 1)
      line = substr($0, RSTART + 1, RLENGTH - 3) + 0
      for (i = 1; i <= n; i++) if (p[i] == path && line >= s[i] && line <= e[i]) { print; break }
    }'
}

# checks_refuse_partly_staged: a rewriting check calls this before it rewrites.
# Each staged path that also has unstaged changes gets the contract line on
# stderr; returns 1 when any did, since re-staging a rewrite would stage the
# unstaged hunks too.
checks_refuse_partly_staged() {
  local f refused=0
  while IFS= read -r -d '' f; do
    if checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done < <(checks_files)
  return "$refused"
}

checks_partly_staged() {
  [[ "$CHECKS_MODE" == pre-commit ]] || return 1
  if [[ ! -f "$CHECKS_TMP/unstaged" ]]; then
    git diff --name-only --no-color -z >"$CHECKS_TMP/unstaged" 2>/dev/null || : >"$CHECKS_TMP/unstaged"
  fi
  local f
  while IFS= read -r -d '' f; do
    [[ "$f" == "$1" ]] && return 0
  done <"$CHECKS_TMP/unstaged"
  return 1
}
