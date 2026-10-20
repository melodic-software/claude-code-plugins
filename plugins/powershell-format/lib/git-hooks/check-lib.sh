#!/usr/bin/env bash
# GENERATED from lib/git-hooks/check-lib.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
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
#                              added lines to $CHECKS_TMP/ranges, none for a
#                              file whose content is binary
#   checks_file_text [--tip <sha>] <p> [<rev>]
#                              <p> as the change holds it, on stdout: the
#                              tip's blob (in pre-push with no tip, the tip of
#                              the range <p> changed in), else the work tree in
#                              worktree mode, else the index; returns 1,
#                              printing nothing, when <p> is not a regular
#                              file there (deleted, symlink, submodule)
#   checks_regular_file [--tip <sha>] <p> [<rev>]
#                              0 when <p> is a regular file in that place;
#                              --tip names the tip when two pushed ranges
#                              change the same path
#   checks_has_nul <p> [<rev>] 0 when that content's first 8000 bytes hold a NUL
#   checks_filter_findings     stdin "<path>:<line>: <message>" lines; prints
#                              those inside a changed range
#   checks_partly_staged <p>   0 when <p> has unstaged changes too
#   checks_refuse_partly_staged
#                              a rewriting check calls this first: prints the
#                              contract line per partly staged path, returns 1
#   checks_refuse_config_drift [--if <fn>] <name>... -- <path>...
#                              pre-commit: prints the contract line per config
#                              governing a <path> whose work tree differs from
#                              the index, returns 1
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
  # An all-zero id of any width: 40 hex digits under SHA-1, 64 under SHA-256.
  local remote="${CHECKS_ARGS%% *}" zero='^0+$'
  local lref lsha rsha head base seen=0
  [[ -n "$remote" ]] || remote=origin
  while read -r lref lsha _ rsha; do
    [[ -n "$lsha" ]] || continue
    seen=1
    [[ "$lsha" =~ $zero ]] && continue
    if ! [[ "$rsha" =~ $zero ]]; then
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

# checks_range_tip <path>: pre-push; prints the tip of the first pushed range
# whose base-to-tip diff touches <path>, so a path is read from its own ref.
checks_range_tip() {
  local b l
  while read -r b l; do
    git diff --quiet "$b" "$l" -- ":(literal)$1" 2>/dev/null && continue
    printf '%s' "$l"
    return 0
  done <"$CHECKS_TMP/push-ranges"
  return 1
}

# checks_tip_arg: the shared "[--tip <sha>] <path> [<rev>]" parse; sets tip
# and path. <rev> is the older spelling of --tip.
checks_tip_arg() {
  tip=""
  if [[ "${1:-}" == --tip ]]; then
    tip="$2"
    shift 2
  fi
  path="$1"
  [[ -n "$tip" ]] || tip="${2:-}"
}

# checks_regular_file [--tip <sha>] <path> [<rev>]: a regular file, not a
# symlink or a submodule entry, where checks_file_text reads it: the tip's
# tree, else the work tree in worktree mode, else the index. In pre-push with
# no tip, the tip of the range that changed <path>, never the work tree.
checks_regular_file() {
  local tip path entry
  checks_tip_arg "$@"
  if [[ -z "$tip" ]]; then
    case "$CHECKS_MODE" in
    worktree)
      [[ -f "$path" && ! -L "$path" ]]
      return
      ;;
    pre-push) tip="$(checks_range_tip "$path")" || return 1 ;;
    *)
      entry="$(git ls-files -s -z -- ":(literal)$path" 2>/dev/null | tr -d '\0')"
      [[ "$entry" == 100* && "${entry#*$'\t'}" == "$path" ]]
      return
      ;;
    esac
  fi
  entry="$(git ls-tree -z "$tip" -- "$path" 2>/dev/null | tr -d '\0')"
  [[ "$entry" == 100* && "${entry#*$'\t'}" == "$path" ]]
}

# checks_file_text [--tip <sha>] <path> [<rev>]: the content a check judges,
# from the place checks_regular_file looks. A path that is not a regular file
# there returns 1 with no output, so it is never judged as an empty file.
checks_file_text() {
  local tip path
  checks_tip_arg "$@"
  if [[ -z "$tip" && "$CHECKS_MODE" == pre-push ]]; then
    tip="$(checks_range_tip "$path")" || return 1
  fi
  checks_regular_file --tip "$tip" "$path" || return 1
  if [[ -n "$tip" ]]; then
    git show "$tip:$path" 2>/dev/null
  elif [[ "$CHECKS_MODE" == worktree ]]; then
    cat -- "$path"
  else
    git show ":$path" 2>/dev/null
  fi
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
#
# --text keeps a `-diff` attribute from hiding a text file's hunks, so a file
# is dropped here instead when the content the change holds is binary
# (checks_has_nul): no caller then sees ranges for it.
checks_changed_lines() {
  local out="$CHECKS_TMP/ranges" raw="$CHECKS_TMP/ranges.raw"
  : >"$raw"
  checks_diff -U0 --text --diff-filter=ACMR --src-prefix=a/ --dst-prefix=b/ 2>/dev/null |
    awk '
      /^\+\+\+ / { path = substr($0, 5); sub(/\t$/, "", path); if (path ~ /^b\//) path = substr(path, 3); else path = ""; next }
      /^@@ / && path != "" {
        split($3, n, ",")
        start = substr(n[1], 2) + 0
        count = (n[2] == "") ? 1 : n[2] + 0
        if (count > 0) printf "%s\t%d\t%d\n", path, start, start + count - 1
      }' >>"$raw"
  if [[ "$CHECKS_MODE" == worktree ]]; then
    local f
    while IFS= read -r -d '' f; do
      printf '%s\t1\t2147483647\n' "$f" >>"$raw"
    done < <(git ls-files --others --exclude-standard -z)
  fi
  local p s e prev="" bin=0
  : >"$out"
  while IFS=$'\t' read -r p s e; do
    if [[ "$p" != "$prev" ]]; then
      prev="$p"
      bin=0
      checks_change_has_nul "$p" && bin=1
    fi
    ((bin)) || printf '%s\t%s\t%s\n' "$p" "$s" "$e" >>"$out"
  done <"$raw"
}

# checks_has_nul <path> [<rev>]: 0 when the first 8000 bytes of
# checks_file_text hold a NUL, the binary test git itself applies. The bytes
# decide, never a `-diff` attribute. Builtins only: a check may run with a
# PATH that holds little beyond git. read stops at the first NUL, so fewer
# than 8000 bytes read without reaching the end means one was found.
checks_has_nul() {
  local LC_ALL=C chunk
  IFS= read -r -d '' -n 8000 chunk < <(checks_file_text "$1" "${2:-}") && ((${#chunk} < 8000))
}

# checks_change_has_nul <path>: checks_has_nul against what is checked; on
# pre-push, each pushed commit that holds <path>.
checks_change_has_nul() {
  [[ "$CHECKS_MODE" == pre-push ]] || {
    checks_has_nul "$1"
    return
  }
  local b l
  while read -r b l; do
    checks_has_nul "$1" "$l" && return 0
  done <"$CHECKS_TMP/push-ranges"
  return 1
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

# checks_refuse_config_drift [--if <fn>] <name>... -- <path>...: pre-commit
# only. A check reads its config from the work tree but the commit holds the
# index, so each config file called <name> in a <path>'s directory or above it
# that the index holds and the work tree changes or deletes gets the contract
# line on stderr; returns 1 when any did. An untracked config is not drift: it
# is the repository's config being set up. With --if, a drifted file counts only
# when <fn> <file> returns 0.
checks_refuse_config_drift() {
  [[ "$CHECKS_MODE" == pre-commit ]] || return 0
  local filter=""
  if [[ "${1:-}" == --if ]]; then
    filter="$2"
    shift 2
  fi
  local -a specs=()
  while [[ $# -gt 0 && "$1" != -- ]]; do
    specs+=(":(glob)**/$1")
    shift
  done
  shift
  local c dir f refused=0
  while IFS= read -r -d '' c; do
    [[ -z "$filter" ]] || "$filter" "$c" || continue
    dir="${c%/*}"
    [[ "$dir" == "$c" ]] && dir=.
    for f in "$@"; do
      if [[ "$dir" == . || "$f" == "$dir"/* ]]; then
        printf '%s: config differs between the index and the work tree; stage it or restore it, then commit\n' "$c" >&2
        refused=1
        break
      fi
    done
  done < <(git diff --name-only --no-color -z -- "${specs[@]}" 2>/dev/null)
  return "$refused"
}
