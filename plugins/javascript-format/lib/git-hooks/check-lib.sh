#!/bin/sh
# GENERATED from lib/git-hooks/check-lib.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# shellcheck shell=bash
# Shared helpers for git-hook check scripts: the file set, the changed lines,
# the push range, the missing-tool skip key and agent detection. A check script
# sources this file from its own directory before it runs any bash syntax.
# The contract is the check-placement convention's check-script runtime table.
#
# Git runs a hook under sh, and on Windows a `bash` looked up by name can be
# System32's WSL launcher, so a check script starts as POSIX sh and the block
# below, POSIX sh too, puts it under bash. It looks for the first bash on PATH
# that is not in System32, Sysnative or WindowsApps. Under a sh that is not
# bash it reruns the script under that bash, once: CHECKS_REEXEC marks the
# rerun, so a `bash` that is not bash cannot loop. With none, bash is a missing
# tool under the contract's rule. Under bash already, POSIX mode goes off; when
# that bash started as sh, and so in POSIX mode, the bash found is the one
# checks_bash_run starts a check's own bash scripts with.
#
# Names are POSIX-safe (checks_files, not checks::files) and the syntax stays
# within bash 3.2, which is what macOS ships: no associative arrays, no
# mapfile, no ${var,,}. Every git call that can legitimately fail (an unset
# config key, a missing ref) is guarded, so the helpers also hold under set -e.
#
#   checks_init <event> "$@"   set CHECKS_MODE (pre-commit, pre-push or, with
#                              --worktree, worktree), CHECKS_EVENT, CHECKS_TMP,
#                              and cd to the top level; returns 1 outside a repo
#   checks_files               NUL-separated paths to check, repo-relative; in
#                              pre-commit while a merge is in progress, only
#                              paths that differ from every parent
#   checks_changed_lines       write "<path><TAB><start><TAB><end>" ranges of
#                              added lines to $CHECKS_TMP/ranges, none for a
#                              file whose content is binary; in pre-commit
#                              while a merge is in progress, only the lines no
#                              parent holds
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
#   When git, awk or tr fails inside checks_changed_lines or checks_filter_findings,
#   the function says so on stderr and returns non-zero, and the script then
#   exits 1 even when it exits 0 itself: a check that saw only part of the
#   change must not pass it.
#   checks_partly_staged <p>   0 when <p> has unstaged changes too
#   checks_staged_gone <p>     pre-commit: 0 when <p> is gone from the work
#                              tree and the index holds it as a regular file
#   checks_refuse_partly_staged
#                              a rewriting check calls this first: prints the
#                              contract line per partly staged path, returns 1
#   checks_restage <path>...   a rewriting check calls this after it rewrites:
#                              prints and stages each <path> whose work tree
#                              now differs from the index
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
#   checks_bash_run <script> [args...]
#                              run a bash script in a child bash with POSIX
#                              mode off, never a bash found by name

# checks_as: sh (not bash), posix (bash started as sh) or empty (bash).
# shellcheck disable=SC2086,SC2292 # POSIX sh until bash runs it: PATH and the skip list split unquoted, no [[ ]]
{
  checks_as=""
  checks_bash=""
  if [ -z "${BASH_VERSION:-}" ]; then
    checks_as="sh"
  else
    case ":${SHELLOPTS:-}:" in
    *:posix:*) checks_as="posix" ;;
    *) ;;
    esac
  fi
  checks_ifs=$IFS
  if [ -n "$checks_as" ]; then
    IFS=:
    set -f
    for checks_dir in $PATH; do
      case "$checks_dir" in
      /* | [A-Za-z]:[\\/]*) ;;
      *) continue ;;
      esac
      case "${checks_dir%[\\/]}" in
      *[\\/][Ss][Yy][Ss][Tt][Ee][Mm]32 | *[\\/][Ss][Yy][Ss][Nn][Aa][Tt][Ii][Vv][Ee] | *[\\/][Ww][Ii][Nn][Dd][Oo][Ww][Ss][Aa][Pp][Pp][Ss] | *[\\/][Ww][Ii][Nn][Dd][Oo][Ww][Ss][Aa][Pp][Pp][Ss][\\/]*) continue ;;
      *) ;;
      esac
      if [ -f "$checks_dir/bash" ] && [ -x "$checks_dir/bash" ]; then
        checks_bash="$checks_dir/bash"
        break
      fi
    done
    set +f
    IFS=$checks_ifs
  fi
  if [ "$checks_as" = sh ]; then
    if [ -n "$checks_bash" ] && [ -z "${CHECKS_REEXEC:-}" ]; then
      CHECKS_REEXEC=1
      export CHECKS_REEXEC
      exec "$checks_bash" "$0" "$@"
    fi
    checks_skip=$(git config --get checks.skipmissing 2>/dev/null) || checks_skip=""
    IFS=,
    set -f
    for checks_item in $checks_skip; do
      checks_item="${checks_item#"${checks_item%%[![:space:]]*}"}"
      checks_item="${checks_item%"${checks_item##*[![:space:]]}"}"
      if [ "$checks_item" = bash ]; then
        echo 'SKIPPED: bash (missing)' >&2
        exit 0
      fi
    done
    set +f
    IFS=$checks_ifs
    checks_install='bash from the system package manager (on Windows, Git for Windows); System32 bash is the WSL launcher and is never used'
    if [ "${CLAUDECODE:-}" = 1 ] || [ -n "${AI_AGENT:-}" ]; then
      printf 'FAIL: bash missing. Install: %s\n' "$checks_install" >&2
      echo 'To skip only while bash is missing: git -c checks.skipmissing=bash commit ... (or push ...)' >&2
      exit 1
    fi
    printf 'NOTICE: bash missing, so this check did not run. Install: %s\n' "$checks_install" >&2
    exit 0
  fi
  unset CHECKS_REEXEC
  # The bash checks_bash_run starts: this one, unless it started as sh; then
  # the bash found, and with none, this one with POSIX mode turned off.
  if [ "$checks_as" = posix ]; then
    CHECKS_CHILD_BASH=$checks_bash
  else
    CHECKS_CHILD_BASH=$BASH
  fi
  set +o posix
}

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
  # One rev-parse names the top level and MERGE_HEAD, whose path is relative
  # to the starting directory, so the merge heads are read before the cd. If
  # the combined call fails, --show-toplevel alone decides, with no merge.
  local top out merge_file="" line
  if out="$(git rev-parse --show-toplevel --git-path MERGE_HEAD 2>/dev/null)" && [[ "$out" == *$'\n'* ]]; then
    top="${out%$'\n'*}"
    merge_file="${out##*$'\n'}"
  else
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  fi
  CHECKS_MERGE_HEADS=""
  if [[ "$CHECKS_MODE" == pre-commit && -n "$merge_file" && -f "$merge_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] || CHECKS_MERGE_HEADS="$CHECKS_MERGE_HEADS$line"$'\n'
    done <"$merge_file"
  fi
  cd "$top" || return 1
  CHECKS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/checks.XXXXXX")" || return 1
  trap 'checks_finish $? || exit 1' EXIT
  if [[ "$CHECKS_MODE" == pre-push ]]; then
    checks_push_ranges >"$CHECKS_TMP/push-ranges"
  fi
  return 0
}

# checks_finish <status>: the EXIT trap checks_init sets, with the status the
# script exits with. Removes CHECKS_TMP; returns 1 when that status is 0 but a
# tool the lib ran failed (checks_tool_failed), so the trap exits 1. A script
# that sets its own EXIT trap calls this from it the same way.
checks_finish() {
  local failed=0
  [[ -e "$CHECKS_TMP/tool-failed" ]] && failed=1
  rm -rf "$CHECKS_TMP"
  ((${1:-0} != 0 || !failed))
}

# checks_tool_failed <tool> <status> <step>: a tool the lib ran while <step>
# failed, so the change was not fully checked. Says so on stderr and leaves the
# marker checks_finish reads, a file because a caller in a pipeline runs in a
# subshell.
checks_tool_failed() {
  printf '%s: %s exited %s while %s, so this change was not fully checked; fix that failure, then %s again\n' \
    "${0##*/}" "$1" "$2" "$3" "$(checks_git_verb)" >&2
  : >>"$CHECKS_TMP/tool-failed"
}

checks_is_agent() {
  [[ "${CLAUDECODE:-}" == 1 || -n "${AI_AGENT:-}" ]]
}

# checks_bash_run <script> [args...]: run <script> under CHECKS_CHILD_BASH
# (set above). When that is empty, this bash started as sh with no other bash
# on PATH outside System32, and a child it starts would start in POSIX mode too:
# then the child turns POSIX mode off and sources the script with its
# arguments, so $0 and BASH_SOURCE[0] both name the script as when it runs on
# its own.
checks_bash_run() {
  if [[ -n "$CHECKS_CHILD_BASH" ]]; then
    "$CHECKS_CHILD_BASH" "$@"
    return
  fi
  # shellcheck disable=SC2016 # $0 and $@ are the child's
  "$BASH" -c 'set +o posix; shopt -u sourcepath; . "$0" "$@"' "$@"
}

# git config --get exits 1 for an unset key; that is an empty list, not an error.
checks_skip_listed() {
  local list item
  list="$(git config --get checks.skipmissing 2>/dev/null || true)"
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
  local tool="$1" install="$2"
  command -v "$tool" >/dev/null 2>&1 && return 0
  if checks_skip_listed "$tool"; then
    printf 'SKIPPED: %s (missing)\n' "$tool" >&2
    exit 0
  fi
  if checks_is_agent; then
    printf 'FAIL: %s missing. Install: %s\n' "$tool" "$install" >&2
    printf 'To skip only while %s is missing: git -c checks.skipmissing=%s %s ...\n' "$tool" "$tool" "$(checks_git_verb)" >&2
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
      if git cat-file -e "$rsha^{commit}" 2>/dev/null; then
        printf '%s %s\n' "$rsha" "$lsha"
        continue
      fi
      # A remote sha this clone lacks (a push over an unfetched commit)
      # ranges like a new branch, so git diff never fails on a missing object.
      printf 'NOTICE: %s is not in this clone, so %s is checked from its merge-base with the default branch; fetch to check against the remote.\n' "$rsha" "$lref" >&2
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
  pre-commit) git -c core.quotePath=false diff --cached --no-color --no-ext-diff "$@" -- ;;
  worktree)
    local base=HEAD
    git rev-parse --verify --quiet HEAD >/dev/null 2>&1 || base="$CHECKS_EMPTY_TREE"
    git -c core.quotePath=false diff "$base" --no-color --no-ext-diff "$@" --
    ;;
  pre-push)
    # The status is the first failing range's, not only the last range's.
    local b l s rc=0
    while read -r b l; do
      git -c core.quotePath=false diff "$b" "$l" --no-color --no-ext-diff "$@" --
      s=$?
      ((rc)) || rc=$s
    done <"$CHECKS_TMP/push-ranges"
    return "$rc"
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
  if [[ -n "$tip" || "$CHECKS_MODE" == pre-push ]]; then
    [[ -n "$tip" ]] || tip="$(checks_range_tip "$path")" || return 1
    entry="$(git ls-tree -z "$tip" -- "$path" 2>/dev/null | tr -d '\0')"
  elif [[ "$CHECKS_MODE" == worktree ]]; then
    [[ -f "$path" && ! -L "$path" ]]
    return
  else
    entry="$(git ls-files -s -z -- ":(literal)$path" 2>/dev/null | tr -d '\0')"
  fi
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
  checks_merge_own_files && return 0
  checks_diff --name-only --diff-filter=ACMR -z
  if [[ "$CHECKS_MODE" == worktree ]]; then
    git ls-files --others --exclude-standard -z
  fi
}

# checks_added_ranges <file> <diff filter> [<rev>]: append the checks_diff
# ranges of added lines, for the files whose status <diff filter> names, to
# <file>; in pre-commit, <rev> diffs the index against that commit instead of
# HEAD. Hunk headers read "@@ -a[,b] +c[,d] @@"; d defaults to 1 and d=0 adds
# nothing. Paths come from "+++ b/<path>", where git appends a tab to a name
# holding a space; a name git still quotes is skipped. Each hunk's b old-side
# and d new-side lines are consumed as content, so an added line whose text
# starts "++ b/" (printed "+++ b/") is never read as a file header.
# --inter-hunk-context=0 overrides a diff.interHunkContext setting that would
# fuse hunks and widen a range over unchanged lines. --text keeps a `-diff`
# attribute from hiding a text file's hunks. LC_ALL=C reads each line byte-wise,
# so a non-UTF-8 content line (a UTF-16 or ANSI file) draws no multibyte warning.
checks_added_ranges() {
  local raw="$1" filter="$2"
  shift 2
  checks_diff "$@" -U0 --text --diff-filter="$filter" --src-prefix=a/ --dst-prefix=b/ --inter-hunk-context=0 2>/dev/null |
    LC_ALL=C awk '
      left > 0 || right > 0 {
        c = substr($0, 1, 1)
        if (c == " ") { left--; right--; next }
        if (c == "-") { left--; next }
        if (c == "+") { right--; next }
        if (c == "\\") next
      }
      /^\+\+\+ / { path = substr($0, 5); sub(/\t$/, "", path); if (path ~ /^b\//) path = substr(path, 3); else path = ""; next }
      /^@@ / {
        split($2, o, ",")
        left = (o[2] == "") ? 1 : o[2] + 0
        split($3, n, ",")
        start = substr(n[1], 2) + 0
        right = (n[2] == "") ? 1 : n[2] + 0
        if (path != "" && right > 0) printf "%s\t%d\t%d\n", path, start, start + right - 1
      }' >>"$raw"
  # Short ranges would drop findings, so a failed diff or awk fails the hook.
  # A diff stopped by SIGPIPE (141) means awk stopped first, and awk reports.
  local -a st=("${PIPESTATUS[@]}")
  local rc=0
  if ((st[0] != 0 && st[0] != 141)); then
    checks_tool_failed git "${st[0]}" 'listing the changed lines'
    rc=1
  fi
  if ((st[1] != 0)); then
    checks_tool_failed awk "${st[1]}" 'listing the changed lines'
    rc=1
  fi
  return "$rc"
}

# checks_intersect_ranges <a> <b>: the parts of <b>'s ranges that <a>'s ranges
# of the same path cover too, in <b>'s order.
checks_intersect_ranges() {
  awk -F '\t' -v OFS='\t' '
    NR == FNR { n++; f[n] = $1; s[n] = $2 + 0; e[n] = $3 + 0; next }
    { for (i = 1; i <= n; i++) if (f[i] == $1) {
        lo = ($2 + 0 > s[i]) ? $2 + 0 : s[i]; hi = ($3 + 0 < e[i]) ? $3 + 0 : e[i]
        if (lo <= hi) print $1, lo, hi } }' "$1" "$2"
}

# checks_merge_heads: pre-commit; the other parents of the merge being
# committed, one per line (more than one for an octopus merge), none outside a
# merge.
checks_merge_heads() {
  [[ "$CHECKS_MODE" == pre-commit ]] || return 0
  printf '%s' "${CHECKS_MERGE_HEADS:-}"
}

# checks_merge_own_files: pre-commit while a merge is in progress; prints,
# NUL-separated, the checks_files paths whose staged entry (mode and blob)
# differs from every merge head's, and returns 0. A path is kept when it is in
# the list against HEAD and in the list against each head, so it appears once
# per list in the sorted union. Returns 1, printing nothing, outside a merge,
# and after one line on stderr when a git call or the sort fails or the sort
# did not sort: checks_files then lists every staged path, so a failure checks
# more, never less, and never fails the hook.
checks_merge_own_files() {
  [[ "$CHECKS_MODE" == pre-commit && -n "${CHECKS_MERGE_HEADS:-}" ]] || return 1
  [[ ! -e "$CHECKS_TMP/merge-fallback" ]] || return 1
  local all="$CHECKS_TMP/merge-paths" want=1 h step=""
  if checks_diff --name-only --diff-filter=ACMR -z >"$all" 2>/dev/null; then
    while IFS= read -r h; do
      [[ -n "$h" ]] || continue
      git -c core.quotePath=false diff --cached --no-color --no-ext-diff --name-only --no-renames -z "$h" -- >>"$all" 2>/dev/null || {
        step='git'
        break
      }
      want=$((want + 1))
    done <<<"$CHECKS_MERGE_HEADS"
  else
    step='git'
  fi
  if [[ -z "$step" ]]; then
    LC_ALL=C sort -z "$all" >"$all.sorted" 2>/dev/null || step='sort'
  fi
  local -a kept=()
  if [[ -z "$step" ]]; then
    local LC_ALL=C p prev="" run=0
    while IFS= read -r -d '' p; do
      if ((run)) && [[ "$p" == "$prev" ]]; then
        run=$((run + 1))
        continue
      fi
      if ((run)); then
        # Out of order or a run longer than the list count: the sort did not
        # sort, so no run can be trusted.
        if ((run > want)) || ! [[ "$prev" < "$p" ]]; then
          step='sort'
          break
        fi
        ((run < want)) || kept+=("$prev")
      fi
      prev="$p"
      run=1
    done <"$all.sorted"
    if [[ -z "$step" ]] && ((run)); then
      if ((run > want)); then
        step='sort'
      elif ((run == want)); then
        kept+=("$prev")
      fi
    fi
  fi
  if [[ -n "$step" ]]; then
    printf '%s: %s failed while listing the paths this merge changes, so every staged path is checked\n' "${0##*/}" "$step" >&2
    : >"$CHECKS_TMP/merge-fallback"
    return 1
  fi
  if ((${#kept[@]})); then
    printf '%s\0' "${kept[@]}"
  fi
  return 0
}

# A file whose content the change holds is binary (checks_binary_paths) is
# dropped here, since checks_added_ranges reads every file as text: no caller
# then sees ranges for it.
checks_changed_lines() {
  local out="$CHECKS_TMP/ranges" raw="$CHECKS_TMP/ranges.raw" rc=0 m
  : >"$raw"
  checks_added_ranges "$raw" ACMR || rc=1
  # A merge being committed adds only the lines no parent holds, its conflict
  # resolution: a line another parent already holds is that branch's content,
  # not this commit's. With T, a file that parent holds as a symlink or a
  # submodule counts every line as added against it.
  while read -r m; do
    : >"$raw.other"
    checks_added_ranges "$raw.other" ACMRT "$m" || rc=1
    checks_intersect_ranges "$raw.other" "$raw" >"$raw.both" || {
      checks_tool_failed awk "$?" 'listing the lines the merge adds'
      rc=1
    }
    mv "$raw.both" "$raw"
  done < <(checks_merge_heads)
  if [[ "$CHECKS_MODE" == worktree ]]; then
    local f
    while IFS= read -r -d '' f; do
      printf '%s\t1\t2147483647\n' "$f" >>"$raw"
    done < <(git ls-files --others --exclude-standard -z)
  fi
  local bin="$CHECKS_TMP/binary"
  checks_binary_paths "$raw" "$bin" || rc=1
  awk -F '\t' -v bin="$bin" '
    BEGIN { while ((got = (getline b < bin)) > 0) drop[b] = 1; if (got < 0) exit 2 }
    !($1 in drop)' "$raw" >"$out" || {
    checks_tool_failed awk "$?" 'listing the changed lines'
    rc=1
  }
  return "$rc"
}

# checks_binary_paths <ranges> <out>: write to <out>, one per line, each path
# of <ranges> that checks_has_nul finds binary where the change holds it (on
# pre-push, at any pushed tip), with a fixed number of processes however many
# paths there are: builtins in worktree mode, else checks_nul_blobs over the
# index or over each pushed tip.
checks_binary_paths() {
  local ranges="$1" out="$2" rc=0 p prev="" l
  : >"$out"
  [[ -s "$ranges" ]] || return 0
  case "$CHECKS_MODE" in
  worktree)
    while IFS=$'\t' read -r p _; do
      [[ "$p" == "$prev" ]] && continue
      prev="$p"
      checks_worktree_has_nul "$p" && printf '%s\n' "$p" >>"$out"
    done <"$ranges"
    ;;
  pre-push)
    while read -r _ l; do
      checks_nul_blobs "$ranges" "$out" 3 ls-tree -r "$l" || rc=1
    done <"$CHECKS_TMP/push-ranges"
    ;;
  *) checks_nul_blobs "$ranges" "$out" 2 ls-files -s || rc=1 ;;
  esac
  return "$rc"
}

# checks_worktree_has_nul <path>: checks_has_nul for a work tree file, read
# with builtins.
checks_worktree_has_nul() {
  local LC_ALL=C chunk
  [[ -f "$1" && ! -L "$1" ]] || return 1
  IFS= read -r -d '' -n 8000 chunk <"$1" && ((${#chunk} < 8000))
}

# checks_nul_blobs <ranges> <out> <oid field> <git listing args...>: append to
# <out> each path of <ranges> that the listing (ls-files -s, or ls-tree -r
# <tip>, whose oid is field 2 or 3) holds as a regular file whose blob's first
# 8000 bytes hold a NUL. A listed name git quotes never matches, as
# checks_added_ranges skips those names. One git cat-file --batch streams the
# blobs, each as "<oid> blob <size>" LF <bytes> LF, so a header always has a
# line of its own and no line holds bytes of two blobs. tr turns every NUL into
# a \001 and every \001 and every byte above \177 into a \002, as awk cannot
# hold a NUL and an awk that reads UTF-8 whatever the locale (the One True AWK's
# second edition) would count a multibyte character as one; the stream is then
# ASCII, one byte per character, so the last awk's length() counts bytes to find
# each header and each blob's first 8000, and fails on a stream whose length
# does not match its headers.
checks_nul_blobs() {
  local ranges="$1" out="$2" field="$3" sel="$CHECKS_TMP/nul-blobs"
  shift 3
  : >"$sel"
  git -c core.quotePath=false "$@" </dev/null 2>/dev/null |
    LC_ALL=C awk -v ranges="$ranges" -v sel="$sel" -v field="$field" '
      BEGIN {
        while ((got = (getline r < ranges)) > 0) want[substr(r, 1, index(r, "\t") - 1)] = 1
        if (got < 0) exit 2
      }
      {
        t = index($0, "\t")
        if (!t) next
        path = substr($0, t + 1)
        if (!(path in want)) next
        split(substr($0, 1, t - 1), m, " ")
        if (m[1] !~ /^100/) next
        print m[field] "\t" path >sel
        if (!(m[field] in seen)) { seen[m[field]] = 1; print m[field] }
      }
      END { close(sel) }' |
    git cat-file --batch 2>/dev/null |
    LC_ALL=C tr '\0\001\200-\377' '\001\002\002' |
    LC_ALL=C awk -F '\n' -v sel="$sel" '
      {
        len = length($0)
        if (base == head_at) {
          split($0, f, " ")
          if (f[2] == "missing") {
            blob = ""
            head_at = base + len + 1
          } else {
            blob = f[1]
            start = base + len + 1
            size = f[3] + 0
            window = start + (size < 8000 ? size : 8000)
            blob_end = start + size
            head_at = blob_end + 1
          }
        } else if (blob != "" && base < window && !(blob in bin)) {
          i = index($0, "\001")
          if (i && base + i - 1 < window) bin[blob] = 1
        }
        base += len + 1
      }
      END {
        if (head_at != base) exit 2
        while ((got = (getline r < sel)) > 0) {
          t = index(r, "\t")
          if (substr(r, 1, t - 1) in bin) print substr(r, t + 1)
        }
        if (got < 0) exit 2
      }' >>"$out"
  local -a st=("${PIPESTATUS[@]}")
  local -a tools=(git awk git tr awk)
  local i rc=0
  for i in 0 1 2 3 4; do
    # 141: a reader further down stopped first, and that reader reports.
    ((st[i] == 0 || (i < 4 && st[i] == 141))) && continue
    checks_tool_failed "${tools[i]}" "${st[i]}" 'testing the changed files for binary content'
    rc=1
  done
  return "$rc"
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

# A ranges file it cannot read (checks_changed_lines never ran) fails like a
# failed awk: with no ranges every finding would drop.
checks_filter_findings() {
  local rc
  awk -v ranges="$CHECKS_TMP/ranges" '
    BEGIN {
      while ((got = (getline l < ranges)) > 0) { split(l, r, "\t"); n++; p[n] = r[1]; s[n] = r[2] + 0; e[n] = r[3] + 0 }
      if (got < 0) exit 2
    }
    {
      if (!match($0, /:[0-9]+: /)) next
      path = substr($0, 1, RSTART - 1)
      line = substr($0, RSTART + 1, RLENGTH - 3) + 0
      for (i = 1; i <= n; i++) if (p[i] == path && line >= s[i] && line <= e[i]) { print; break }
    }'
  rc=$?
  # 141: a reader closed the pipe once it had what it needed.
  ((rc == 0 || rc == 141)) || checks_tool_failed awk "$rc" 'filtering the findings to the changed lines'
  return "$rc"
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

# checks_restage <path>...: after a rewrite, prints one per line each <path>
# whose work tree differs from the index, in git's order, and stages them.
# Windows caps a command line at 32,767 characters, so no git call carries the
# paths: the diff lists every unstaged change and the <path>s are picked out of
# it, and git add (2.25 or later) reads them NUL-separated from stdin. A failed
# git call says so on stderr and returns 1, and the hook then exits 1.
checks_restage() {
  # %q spells every name on one line, so a name holding an LF stays one entry.
  # The names are kept in one LF-joined list per spelled length, so a lookup
  # scans only the names of its own length. LC_ALL=C keeps the match byte-wise.
  local LC_ALL=C nl=$'\n' f q
  local -a want=() rewritten=()
  for f in "$@"; do
    printf -v q '%q' "$f"
    want[${#q}]="${want[${#q}]:-$nl}$q$nl"
  done
  git diff --name-only --no-color --no-ext-diff --ignore-submodules=all -z >"$CHECKS_TMP/restage" || {
    checks_tool_failed git "$?" 'listing the rewritten files'
    return 1
  }
  while IFS= read -r -d '' f; do
    printf -v q '%q' "$f"
    if [[ "${want[${#q}]:-}" == *"$nl$q$nl"* ]]; then
      rewritten+=("$f")
    fi
  done <"$CHECKS_TMP/restage"
  ((${#rewritten[@]})) || return 0
  printf '%s\n' "${rewritten[@]}"
  printf '%s\0' "${rewritten[@]}" | git --literal-pathspecs add --pathspec-from-file=- --pathspec-file-nul || {
    checks_tool_failed git "$?" 'staging the rewritten files'
    return 1
  }
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

# checks_staged_gone <path>: 0 at pre-commit when <path> is gone from the work tree and
# the index holds it as a regular file, not a symlink (mode 120000) or a submodule.
checks_staged_gone() {
  [[ "$CHECKS_MODE" == pre-commit && ! -e "$1" && ! -L "$1" ]] || return 1
  [[ "$(git ls-files -s -- ":(literal)$1" 2>/dev/null)" == 100* ]]
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
