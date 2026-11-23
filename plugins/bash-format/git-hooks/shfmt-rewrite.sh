# shellcheck shell=bash

section_applies_to_shell() {
  [[ "$1" =~ \*\.(sh|bash)([^[:alnum:]]|$) || "$1" =~ [{,](sh|bash)[,}] ]]
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
  SHFMT_NOTE+="${SHFMT_NOTE:+ }$1"
}

SUBSCRIPT_ORIG=""
SUBSCRIPT_GUARD=0
subscript_guard_begin() {
  local LC_ALL=C
  SUBSCRIPT_GUARD=0
  # read returns 0 only when it stopped at a NUL before end of file.
  IFS= read -r -d '' SUBSCRIPT_ORIG <"$1" && return 0
  SUBSCRIPT_GUARD=1
}

subscript_spans() {
  shfmt "$2" --filename "$1" 2>/dev/null |
    jq -r '.. | objects | select(.Index? | type == "object") | .Index | "\(.Pos.Offset) \(.End.Offset) \(.Pos.Line)"' 2>/dev/null
}

SUBSCRIPT_TEXT=""
subscript_text() {
  local src="$1" s="$2" e="$3"
  while ((s > 0)) && [[ "${src:s-1:1}" == [[:blank:]] ]]; do s=$((s - 1)); done
  while ((e < ${#src})) && [[ "${src:e:1}" == [[:blank:]] ]]; do e=$((e + 1)); done
  SUBSCRIPT_TEXT="${src:s:e-s}"
}

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
    read -r s e l <<<"${before[i]}"
    subscript_text "$SUBSCRIPT_ORIG" "$s" "$e"
    was="$SUBSCRIPT_TEXT"
    read -r s e _ <<<"${after[i]}"
    subscript_text "$new" "$s" "$e"
    now="$SUBSCRIPT_TEXT"
    [[ "$was" == "$now" ]] && continue
    n=$((n + 1))
    ((n == 1)) && first_was="$was" first_now="$now"
    ((n > 5)) && continue
    ((n > 1)) && named+=", "
    named+="\`[$was]\` on line $l as \`[$now]\`"
  done
  ((n)) || return 0
  ((n > 1)) && noun="the array subscripts" key="each a different key"
  ((n > 5)) && named+=", and $((n - 5)) more"
  printf '%s' "$SUBSCRIPT_ORIG" >"$file"
  shfmt_note "bash-format: shfmt would rewrite $noun $named, $key if the array is associative, so $base was left as written. Quote the key ([\"$first_was\"]) if the array is associative; if it is indexed, write it as shfmt prints it ([$first_now])."
}

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
  [[ "$file" == -* ]] && file="./$file"
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
