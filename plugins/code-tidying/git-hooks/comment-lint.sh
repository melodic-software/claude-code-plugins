#!/bin/sh
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck shell=bash source=../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  cat <<'EOF'
code-tidying comment-lint: fail a comment a change adds outside the comment posture.

  comment-lint.sh               the staged changes (git runs it as pre-commit)
  comment-lint.sh --worktree    the uncommitted changes against HEAD, untracked files included

Reads the team file <home>/code-tidying.yaml: comment_lint (off, the default, report or
block), comment_lint_allow (extended regular expressions a comment may match),
comment_lint_exclude (path globs of files the lint skips, each skip named on stderr:
* and ? stay within one path segment, ** spans segments) and comment_adr_dir (the
decision-record folder, default docs/adr).
comment_posture and class_c_max_lines (the most lines a linked comment paragraph may
run, default 2) come from the team file and the personal override; a userConfig value
never reaches a git hook. explanatory (and strict, balanced, conservative)
runs nothing; auto and aggressive read as necessary.

Judges the files whose extension code-extensions.txt lists, except one whose first 10
lines match a generated-marker.ere line (sync-managed, @generated, or a whole-file
"do not edit" notice; each skip is named on stderr), through the pygments lexer for
the file's name, or POSIX and Bash token rules for a shell script. Findings print as
<path>:<line>: <message> on stderr; block exits 1, report exits 0. A file the comment
reader fails on is named on stderr while the other files are still judged, and blocks
like any tool failure. An ADR pointer's record is looked up in comment_adr_dir where
the file's text is read: the index, the work tree with --worktree, or the pushed tips.
A missing python3, or a python3 that cannot import pygments, follows
checks.skipmissing (tool names python3 and pygments).
EOF
  exit 0
fi

here="$(cd "$here" && pwd)"
asset() {
  if [[ -f "$here/$1" ]]; then
    printf '%s' "$here/$1"
  else
    printf '%s' "$here/../$2/$1"
  fi
}
judge="$(asset comment-lint.py git-hooks)"
settings="$(asset comment-settings.sh scripts)"
extensions="$(asset code-extensions.txt scripts)"
marker="$(asset generated-marker.ere scripts)"

checks_init pre-commit "$@" || exit 0

setting() {
  awk -F '\t' -v k="$1" '$1 == k && $2 != "invalid" { print $2; exit }' "$CHECKS_TMP/settings"
}
checks_bash_run "$settings" . >"$CHECKS_TMP/settings" 2>/dev/null
level="$(setting comment_lint)"
case "$level" in
report | block) ;;
*)
  awk -F '\t' '$1 == "comment_lint" && $2 == "invalid" { print "code-tidying: comment_lint " $3 "; the comment lint did not run" }' \
    "$CHECKS_TMP/settings" >&2
  exit 0
  ;;
esac
case "$(setting comment_posture)" in
none) posture=none ;;
explanatory | strict | balanced | conservative) exit 0 ;;
*) posture=necessary ;;
esac

checks_require_tool python3 "python 3 from https://www.python.org/downloads/ or the system package manager, then python3 -m pip install pygments"
pygments_missing() {
  if checks_skip_listed pygments; then
    printf 'SKIPPED: pygments (missing)\n' >&2
    exit 0
  fi
  if checks_is_agent; then
    printf 'FAIL: pygments missing. Install: python3 -m pip install pygments\n' >&2
    printf 'To skip only while pygments is missing: git -c checks.skipmissing=pygments %s ...\n' "$(checks_git_verb)" >&2
    exit 1
  fi
  printf 'NOTICE: pygments missing, so this check did not run. Install: python3 -m pip install pygments\n' >&2
  exit 0
}

exts=" $(tr -d '\r' <"$extensions" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ') "
texts="$CHECKS_TMP/text"
mkdir -p "$texts"
: >"$CHECKS_TMP/paths"
generated() {
  grep -qiE -f "$marker" < <(head -n 10 "$1")
}
code_ext() {
  local rc=1
  shopt -s nocasematch
  [[ "$1" == *.* && "$exts" == *" ${1##*.} "* ]] && rc=0
  shopt -u nocasematch
  return "$rc"
}
glob_ere() {
  local g="$1" out="" c i
  for ((i = 0; i < ${#g}; i++)); do
    c="${g:i:1}"
    if [[ "${g:i:3}" == '**/' ]]; then
      out+='(.*/)?'
      i=$((i + 2))
    elif [[ "${g:i:2}" == '**' ]]; then
      out+='.*'
      i=$((i + 1))
    elif [[ "$c" == '*' ]]; then
      out+='[^/]*'
    elif [[ "$c" == '?' ]]; then
      out+='[^/]'
    elif [[ "$c" == [[:alnum:]/_-] ]]; then
      out+="$c"
    elif [[ "$c" == [\\^] ]]; then
      out+="\\$c"
    else
      out+="[$c]"
    fi
  done
  printf '^%s$' "$out"
}
excludes=()
exclude_res=()
while IFS= read -r g; do
  excludes+=("$g")
  exclude_res+=("$(glob_ere "$g")")
done < <(checks_bash_run "$settings" --list comment_lint_exclude .)
excluded_by() {
  local i
  for i in "${!exclude_res[@]}"; do
    [[ "$1" =~ ${exclude_res[i]} ]] && printf '%s' "${excludes[i]}" && return 0
  done
  return 1
}
made=""
while IFS= read -r -d '' f; do
  code_ext "${f##*/}" || continue
  if glob="$(excluded_by "$f")"; then
    printf 'code-tidying: comment lint skipped %s (comment_lint_exclude: %s)\n' "$f" "$glob" >&2
    continue
  fi
  dir="$texts/${f%/*}"
  [[ "$f" == */* ]] || dir="$texts"
  [[ "$dir" == "$made" ]] || mkdir -p "$dir"
  made="$dir"
  checks_file_text "$f" >"$texts/$f" || continue
  if generated "$texts/$f"; then
    printf 'code-tidying: comment lint skipped %s (a generated or sync-managed marker in its first 10 lines)\n' "$f" >&2
    continue
  fi
  printf '%s\0' "$f" >>"$CHECKS_TMP/paths"
done < <(checks_files)
[[ -s "$CHECKS_TMP/paths" ]] || exit 0

records="$CHECKS_TMP/records"
adr_dir="$(setting comment_adr_dir)"
[[ -n "$adr_dir" && "$adr_dir" != unset ]] || adr_dir=docs/adr
adr_records() {
  local l
  if [[ "$CHECKS_MODE" == pre-push ]]; then
    while read -r _ l; do
      git ls-tree -r -z --name-only "$l" -- ":(literal)$adr_dir" 2>/dev/null
    done <"$CHECKS_TMP/push-ranges"
  elif [[ "$CHECKS_MODE" == worktree ]]; then
    git ls-files -co --exclude-standard -z -- ":(literal)$adr_dir"
  else
    git ls-files -z -- ":(literal)$adr_dir"
  fi
}
while IFS= read -r -d '' f; do
  [[ "$CHECKS_MODE" != worktree || -f "$f" ]] || continue
  mkdir -p "$records/${f%/*}" && : >"$records/$f"
done < <(adr_records)

budget=()
max_lines="$(setting class_c_max_lines)"
[[ "$max_lines" =~ ^[0-9]+$ ]] && budget=(--class-c-max-lines "$max_lines")

checks_changed_lines --skip-reindent
checks_diff -U0 --text --diff-filter=ACMR --src-prefix=a/ --dst-prefix=b/ --inter-hunk-context=0 >"$CHECKS_TMP/diff" 2>/dev/null ||
  : >"$CHECKS_TMP/diff"
checks_bash_run "$settings" --list comment_lint_allow . >"$CHECKS_TMP/allow"
python3 "$judge" --posture "$posture" --root "$texts" --records "$records" --adr-dir "$adr_dir" ${budget[@]+"${budget[@]}"} --ranges "$CHECKS_TMP/ranges" --diff "$CHECKS_TMP/diff" --allow "$CHECKS_TMP/allow" \
  <"$CHECKS_TMP/paths" >"$CHECKS_TMP/findings" 2>"$CHECKS_TMP/judge.err"
rc=$?
((rc == 3)) && pygments_missing
cat "$CHECKS_TMP/judge.err" >&2
if ((rc != 0 && rc != 5)); then
  [[ "$level" == block ]] || exit 0
  checks_tool_failed comment-lint.py "$rc" 'judging the added comments'
  exit 1
fi
checks_filter_findings <"$CHECKS_TMP/findings" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] && cat "$CHECKS_TMP/blocking" >&2
[[ "$level" == block ]] || exit 0
if ((rc == 5)); then
  checks_tool_failed comment-lint.py "$rc" 'reading the files named above'
  exit 1
fi
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
exit 1
