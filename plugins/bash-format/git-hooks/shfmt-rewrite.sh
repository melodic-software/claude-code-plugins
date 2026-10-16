# shellcheck shell=bash
# Shared by the pre-commit entry (shell-check.sh) and the PostToolBatch hook
# (hooks/bash-format.sh): which shell files the repository opted in to format,
# and the rewrite itself. Sourced, never run. Stays within bash 3.2.
#
#   shfmt_governed <path>       0 when an .editorconfig section naming shell
#                               files governs the repo-relative path (walk up
#                               to the repository root)
#   editorconfig_shell_section_here <dir>
#                               the walk predicate: 0 hit, 1 none, 2 stop
#   shfmt_rewrite <file>        shfmt in place; sets SHFMT_NOTE when it left
#                               the file as written for a reason worth saying
#
# shfmt runs only for a file an .editorconfig section governs: `[*.sh]`,
# `[*.bash]`, a brace list naming sh or bash, or a path-prefixed form. A bare
# `[*]` is not an opt-in (most repos set only line endings or a charset there),
# and a path-only section such as `[scripts/**]` is not either: matching those
# means reimplementing EditorConfig globbing, so the safe bias is to leave the
# file alone. A `root = true` config with no shell section ends the walk, as
# EditorConfig's own search does.

# $1 is the text inside the brackets.
section_applies_to_shell() {
  local h="$1"
  [[ "$h" =~ \*\.(sh|bash)([^[:alnum:]]|$) ]] && return 0
  [[ "$h" =~ [{,](sh|bash)[,}] ]] && return 0
  return 1
}

editorconfig_shell_section_here() {
  local cfg="$1/.editorconfig" line is_root=0
  [[ -f "$cfg" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]]; then
      section_applies_to_shell "${BASH_REMATCH[1]}" && return 0
    elif [[ "$line" =~ ^[[:space:]]*[Rr][Oo][Oo][Tt][[:space:]]*=[[:space:]]*[Tt][Rr][Uu][Ee][[:space:]]*$ ]]; then
      is_root=1
    fi
  done <"$cfg"
  ((is_root)) && return 2
  return 1
}

shfmt_governed() {
  local dir="${1%/*}" rc
  [[ "$dir" == "$1" ]] && dir=.
  while :; do
    editorconfig_shell_section_here "$dir"
    rc=$?
    ((rc == 0)) && return 0
    ((rc != 1)) && return 1
    [[ "$dir" == . ]] && return 1
    case "$dir" in
    */*) dir="${dir%/*}" ;;
    *) dir=. ;;
    esac
  done
}

SHFMT_NOTE=""
shfmt_note() {
  [[ -n "$SHFMT_NOTE" ]] && SHFMT_NOTE+=" "
  SHFMT_NOTE+="$1"
}

# Subscript guard. shfmt parses an unquoted array subscript as arithmetic,
# because a static parser cannot tell an associative array from an indexed one,
# and spaces its operators: `${m[a-b]}` becomes `${m[a - b]}`, a different key
# (https://github.com/mvdan/sh/issues/956 and the "Caveats" section of the
# mvdan/sh README). The guard compares the source text of every subscript
# before and after the rewrite, in syntax-tree order, and puts the original
# bytes back when any of them differs.
# The tree is the same on both sides, because shfmt reads the spaced and the
# unspaced form as one expression, so the subscripts pair up one to one. A
# span is widened over the blanks beside it before the compare: the tree's
# span leaves out the padding in `${m[ key ]}`, which is part of an
# associative key and which shfmt drops. Offsets are bytes, so the slicing runs
# under LC_ALL=C. A file holding a NUL byte cannot be held in a bash variable
# and is not guarded. A tree that cannot be read on either side, or that
# yields a different number of subscripts, fails closed: the rewrite is put
# back, since an unchecked rewrite may have changed a key.
SUBSCRIPT_ORIG=""
SUBSCRIPT_GUARD=0
subscript_guard_begin() {
  local LC_ALL=C
  SUBSCRIPT_GUARD=0
  # read returns 0 only when it stopped at a NUL before end of file.
  IFS= read -r -d '' SUBSCRIPT_ORIG <"$1" && return 0
  SUBSCRIPT_GUARD=1
}

# subscript_spans <file> <reader>: prints "start end line" for each array
# subscript of the script on stdin; fails when the tree cannot be read. The
# caller's pipefail carries a shfmt failure out of the pipeline, which runs
# shfmt and jq side by side rather than one after the other.
subscript_spans() {
  shfmt "$2" --filename "$1" 2>/dev/null |
    jq -r '.. | objects | select(.Index? | type == "object") | .Index | "\(.Pos.Offset) \(.End.Offset) \(.Pos.Line)"' 2>/dev/null
}

# subscript_text <source> <start> <end>: sets SUBSCRIPT_TEXT to the span
# widened over the blanks on both sides.
SUBSCRIPT_TEXT=""
subscript_text() {
  local src="$1" s="$2" e="$3"
  while ((s > 0)) && [[ "${src:s-1:1}" == [[:blank:]] ]]; do s=$((s - 1)); done
  while ((e < ${#src})) && [[ "${src:e:1}" == [[:blank:]] ]]; do e=$((e + 1)); done
  SUBSCRIPT_TEXT="${src:s:e-s}"
}

# subscript_guard_end <file> <reader>
subscript_guard_end() {
  local file="$1" reader="$2" LC_ALL=C new="" spans span s e l was now i base="${1##*/}"
  local n=0 named="" first_was="" first_now="" noun="the array subscript" key="a different key"
  local -a before=() after=()
  ((SUBSCRIPT_GUARD)) || return 0
  IFS= read -r -d '' new <"$file"
  [[ "$new" == "$SUBSCRIPT_ORIG" ]] && return 0
  if spans=$(subscript_spans "$file" "$reader" <<<"$SUBSCRIPT_ORIG"); then
    while IFS= read -r span; do [[ -n "$span" ]] && before+=("$span"); done <<<"$spans"
    ((${#before[@]})) || return 0
    if spans=$(subscript_spans "$file" "$reader" <<<"$new"); then
      while IFS= read -r span; do [[ -n "$span" ]] && after+=("$span"); done <<<"$spans"
    fi
  fi
  if ((${#before[@]} == 0 || ${#after[@]} != ${#before[@]})); then
    printf '%s' "$SUBSCRIPT_ORIG" >"$file"
    shfmt_note "bash-format: shfmt rewrote $base but its syntax tree could not be read to check array subscripts, so $base was left as written."
    return 0
  fi
  for ((i = 0; i < ${#before[@]}; i++)); do
    span="${before[i]}"
    s="${span%% *}" span="${span#* }"
    e="${span%% *}" l="${span#* }"
    subscript_text "$SUBSCRIPT_ORIG" "$s" "$e"
    was="$SUBSCRIPT_TEXT"
    span="${after[i]}"
    s="${span%% *}" span="${span#* }"
    e="${span%% *}"
    subscript_text "$new" "$s" "$e"
    now="$SUBSCRIPT_TEXT"
    [[ "$was" == "$now" ]] && continue
    n=$((n + 1))
    if ((n == 1)); then
      first_was="$was" first_now="$now"
    elif ((n <= 5)); then
      named+=", "
    fi
    ((n <= 5)) && named+="\`[$was]\` on line $l as \`[$now]\`"
  done
  ((n)) || return 0
  ((n > 1)) && noun="the array subscripts" key="each a different key"
  ((n > 5)) && named+=", and $((n - 5)) more"
  printf '%s' "$SUBSCRIPT_ORIG" >"$file"
  shfmt_note "bash-format: shfmt would rewrite $noun $named, $key if the array is associative, so $base was left as written. Quote the key ([\"$first_was\"]) if the array is associative; if it is indexed, write it as shfmt prints it ([$first_now])."
}

# The flag probe. --apply-ignore (shfmt 3.8+, 2024-02) makes shfmt honor
# `ignore = true` editorconfig rules for a directly named file, which it
# otherwise skips, so a repo's opt-out for generated or vendored scripts holds.
# Older shfmt rejects the flag and cannot honor those rules anyway, so it gets
# a plain in-place format.
#
# The version is decided by PROBING the flag, not by inferring it from a failed
# format run: retrying without the flag after any failure would discard the
# repo's `ignore = true` opt-out and re-format a file the consumer asked shfmt
# to leave alone. Only a confirmed unsupported-flag rejection (the Go flag
# parser's "flag provided but not defined", or a wrapper's "unknown flag",
# naming apply-ignore) takes the plain path. Any other probe failure says
# nothing about the flag, so the file is left untouched and the skip is said.
SHFMT_PROBED=0
SHFMT_APPLY_IGNORE=0
SHFMT_READER=""
SHFMT_PROBE_ERR=""
shfmt_probe() {
  ((SHFMT_PROBED)) && return 0
  local probe_err
  if probe_err=$(shfmt --apply-ignore --version 2>&1 >/dev/null); then
    SHFMT_APPLY_IGNORE=1
    # shfmt before 3.6 has only -tojson, which every release through 3.14.1
    # still accepts with the same subscript offsets.
    SHFMT_READER=--to-json
  elif [[ "$probe_err" == *apply-ignore* ]] &&
    [[ "$probe_err" == *"flag provided but not defined"* || "$probe_err" == *"unknown flag"* ]]; then
    SHFMT_READER=-tojson
  else
    SHFMT_PROBE_ERR="${probe_err%%$'\n'*}"
  fi
  SHFMT_PROBED=1
}

shfmt_rewrite() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  shfmt_probe
  if [[ -n "$SHFMT_PROBE_ERR" ]]; then
    shfmt_note "bash-format: shfmt probe failed ($SHFMT_PROBE_ERR); ${file##*/} not formatted."
    return 0
  fi
  subscript_guard_begin "$file"
  if ((SHFMT_APPLY_IGNORE)); then
    shfmt --apply-ignore -w "$file" 2>/dev/null
  else
    shfmt -w "$file" 2>/dev/null
  fi
  subscript_guard_end "$file" "$SHFMT_READER"
}
