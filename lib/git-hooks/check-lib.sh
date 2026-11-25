#!/bin/sh
# shellcheck shell=bash

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

checks_finish() {
  local failed=0
  [[ -e "$CHECKS_TMP/tool-failed" ]] && failed=1
  rm -rf "$CHECKS_TMP"
  ((${1:-0} != 0 || !failed))
}

checks_tool_failed() {
  printf '%s: %s exited %s while %s, so this change was not fully checked; fix that failure, then %s again\n' \
    "${0##*/}" "$1" "$2" "$3" "$(checks_git_verb)" >&2
  : >>"$CHECKS_TMP/tool-failed"
}

checks_is_agent() {
  [[ "${CLAUDECODE:-}" == 1 || -n "${AI_AGENT:-}" ]]
}

checks_bash_run() {
  if [[ -n "$CHECKS_CHILD_BASH" ]]; then
    "$CHECKS_CHILD_BASH" "$@"
    return
  fi
  # shellcheck disable=SC2016 # $0 and $@ are the child's
  "$BASH" -c 'set +o posix; shopt -u sourcepath; . "$0" "$@"' "$@"
}

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

checks_push_ranges() {
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

checks_diff() {
  case "$CHECKS_MODE" in
  pre-commit) git -c core.quotePath=false diff --cached --no-color --no-ext-diff "$@" -- ;;
  worktree)
    local base=HEAD
    git rev-parse --verify --quiet HEAD >/dev/null 2>&1 || base="$CHECKS_EMPTY_TREE"
    git -c core.quotePath=false diff "$base" --no-color --no-ext-diff "$@" --
    ;;
  pre-push)
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

checks_range_tip() {
  local b l
  while read -r b l; do
    git diff --quiet "$b" "$l" -- ":(literal)$1" 2>/dev/null && continue
    printf '%s' "$l"
    return 0
  done <"$CHECKS_TMP/push-ranges"
  return 1
}

checks_tip_arg() {
  tip=""
  if [[ "${1:-}" == --tip ]]; then
    tip="$2"
    shift 2
  fi
  path="$1"
  [[ -n "$tip" ]] || tip="${2:-}"
}

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

checks_added_ranges() {
  local skip=0
  if [[ "$1" == --skip-reindent ]]; then
    skip=1
    shift
  fi
  local raw="$1" filter="$2"
  shift 2
  checks_diff "$@" -U0 --text --diff-filter="$filter" --src-prefix=a/ --dst-prefix=b/ --inter-hunk-context=0 2>/dev/null |
    LC_ALL=C awk -v skip="$skip" '
      function bare(s) { s = substr(s, 2); sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
      function flush(i, k, lo, hi) {
        for (i = 1; i <= na; i++) {
          k = key[i]
          if (gone[k] > 0) { gone[k]--; continue }
          if (lo && at[i] == hi + 1) { hi++; continue }
          if (lo) printf "%s\t%d\t%d\n", path, lo, hi
          lo = at[i]; hi = lo
        }
        if (lo) printf "%s\t%d\t%d\n", path, lo, hi
        na = 0; split("", gone)
      }
      left > 0 || right > 0 {
        c = substr($0, 1, 1)
        if (c == " ") { left--; right--; line++; next }
        if (c == "-") { left--; if (skip) gone[bare($0)]++; next }
        if (c == "+") { right--; if (path != "") { na++; at[na] = line; key[na] = bare($0) } line++; next }
        if (c == "\\") next
      }
      /^\+\+\+ / { flush(); path = substr($0, 5); sub(/\t$/, "", path); if (path ~ /^b\//) path = substr(path, 3); else path = ""; next }
      /^@@ / {
        split($2, o, ",")
        left = (o[2] == "") ? 1 : o[2] + 0
        split($3, n, ",")
        line = substr(n[1], 2) + 0
        right = (n[2] == "") ? 1 : n[2] + 0
      }
      END { flush() }' >>"$raw"
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

checks_intersect_ranges() {
  awk -F '\t' -v OFS='\t' '
    NR == FNR { n++; f[n] = $1; s[n] = $2 + 0; e[n] = $3 + 0; next }
    { for (i = 1; i <= n; i++) if (f[i] == $1) {
        lo = ($2 + 0 > s[i]) ? $2 + 0 : s[i]; hi = ($3 + 0 < e[i]) ? $3 + 0 : e[i]
        if (lo <= hi) print $1, lo, hi } }' "$1" "$2"
}

checks_merge_heads() {
  [[ "$CHECKS_MODE" == pre-commit ]] || return 0
  printf '%s' "${CHECKS_MERGE_HEADS:-}"
}

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

checks_changed_lines() {
  local -a skip=()
  if [[ "${1:-}" == --skip-reindent ]]; then
    skip=(--skip-reindent)
    shift
  fi
  local out="${1:-$CHECKS_TMP/ranges}" rc=0 m
  local raw="$out.raw"
  : >"$raw"
  checks_added_ranges ${skip[@]+"${skip[@]}"} "$raw" ACMR || rc=1
  while read -r m; do
    : >"$raw.other"
    checks_added_ranges ${skip[@]+"${skip[@]}"} "$raw.other" ACMRT "$m" || rc=1
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

checks_worktree_has_nul() {
  local LC_ALL=C chunk
  [[ -f "$1" && ! -L "$1" ]] || return 1
  IFS= read -r -d '' -n 8000 chunk <"$1" && ((${#chunk} < 8000))
}

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
    ((st[i] == 0 || (i < 4 && st[i] == 141))) && continue
    checks_tool_failed "${tools[i]}" "${st[i]}" 'testing the changed files for binary content'
    rc=1
  done
  return "$rc"
}

checks_has_nul() {
  local LC_ALL=C chunk
  IFS= read -r -d '' -n 8000 chunk < <(checks_file_text "$1" "${2:-}") && ((${#chunk} < 8000))
}

checks_filter_findings() {
  local rc
  awk -v ranges="${1:-$CHECKS_TMP/ranges}" '
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
  ((rc == 0 || rc == 141)) || checks_tool_failed awk "$rc" 'filtering the findings to the changed lines'
  return "$rc"
}

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

# Paths go to git add on stdin: a Windows command line holds at most 32,767 characters:
# https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
checks_restage() {
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

checks_staged_gone() {
  [[ "$CHECKS_MODE" == pre-commit && ! -e "$1" && ! -L "$1" ]] || return 1
  [[ "$(git ls-files -s -- ":(literal)$1" 2>/dev/null)" == 100* ]]
}

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
