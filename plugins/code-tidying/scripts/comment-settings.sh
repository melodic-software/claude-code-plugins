#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE"
[[ -f "$LIB/parse-concern-value.sh" ]] || LIB="$HERE/../lib"
READER="$LIB/parse-concern-value.sh"
KEYS=(comment_posture comment_keep_list comment_edit_scope encode_constraints_unattended class_c_max_lines apply_local_renames comment_lint comment_adr_dir)
TEAM_ONLY_KEYS=" comment_lint comment_adr_dir "
LIST_KEYS=" comment_lint_allow comment_lint_exclude "

help() {
  cat <<'EOF'
Read the code-tidying comment settings from the repository's file layers: the team
file <home>/code-tidying.yaml and the personal override <home>/code-tidying.local.yaml,
the personal override winning key by key. <home> is the bound convention home
(reference/config.md), docs/conventions when none is bound or it was declined.
comment_lint, comment_lint_allow, comment_lint_exclude and comment_adr_dir are read from
the team file only.

Usage: comment-settings.sh [<dir>]
       comment-settings.sh --keep-list <value>
       comment-settings.sh --list comment_lint_allow|comment_lint_exclude [<dir>]

  <dir>        a directory inside the repository; default: the current directory.
  --keep-list  check one comment_keep_list value from another layer (userConfig)
               against the current directory's repository, printing its key line
               with the layer userConfig, or its invalid line.
  --list       print the team file's items for a list key, one per line; nothing
               when the key is unset, the file does not parse (named on stderr)
               or the layer does not apply.

Prints one line per key, tab-separated, and exits 0:
  <key><TAB><value><TAB><file>        the file that supplied the value
  <key><TAB>unset<TAB><reason>        no layer sets a valid value
and, before a key's line, one line per layer that holds an invalid value:
  <key><TAB>invalid<TAB><file>: <what it holds>
A layer that does not apply (no git working tree, a root that is $HOME or an
ancestor of it, a broken pointer) prints every key as unset with that reason. The
caller resolves userConfig and the defaults. Exit 2 on a usage error.
EOF
}

usage() {
  echo "comment-settings: usage: comment-settings.sh [<dir>] | --keep-list <value> | --list comment_lint_allow|comment_lint_exclude [<dir>]" >&2
  exit 2
}
keep_list=""
list_key=""
case "${1:-}" in
-h | --help)
  help
  exit 0
  ;;
--keep-list)
  (($# == 2)) && [[ -n "$2" ]] || usage
  keep_list="$2"
  set --
  ;;
--list)
  (($# == 2 || $# == 3)) && [[ "$LIST_KEYS" == *" $2 "* ]] || usage
  list_key="$2"
  shift 2
  ;;
*) ;;
esac
(($# > 1)) || [[ "${1:-}" == -* ]] && usage
dir="${1:-.}"

valid() {
  case "$1:$2" in
  comment_posture:auto | comment_posture:none | comment_posture:necessary | comment_posture:explanatory) return 0 ;;
  comment_posture:strict | comment_posture:balanced | comment_posture:conservative | comment_posture:aggressive) return 0 ;;
  comment_edit_scope:diff | comment_edit_scope:files) return 0 ;;
  comment_lint:off | comment_lint:report | comment_lint:block) return 0 ;;
  encode_constraints_unattended:true | encode_constraints_unattended:false) return 0 ;;
  apply_local_renames:true | apply_local_renames:false) return 0 ;;
  class_c_max_lines:*) [[ "$2" =~ ^[0-9]+$ ]] && (($2 >= 1 && $2 <= 40)) ;;
  comment_keep_list:default) return 0 ;;
  comment_keep_list:/* | comment_keep_list:..) return 1 ;;
  comment_keep_list:../* | comment_keep_list:*/.. | comment_keep_list:*/../*) return 1 ;;
  comment_keep_list:*) [[ -f "$root/$2" && ! -L "$root/$2" ]] && inside_root "$root/$2" ;;
  comment_adr_dir:/* | comment_adr_dir:.. | comment_adr_dir:../* | comment_adr_dir:*/.. | comment_adr_dir:*/../*) return 1 ;;
  comment_adr_dir:*) [[ ! -e "$root/$2" ]] || inside_root "$root/$2/." ;;
  *) return 1 ;;
  esac
}

inside_root() {
  local parent real_root
  parent="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  real_root="$(cd "$root" && pwd -P)" || return 1
  [[ "$parent" == "$real_root" || "$parent" == "$real_root/"* ]]
}

unset_all() {
  local key
  [[ -n "$list_key" ]] && exit 0
  if [[ -n "$keep_list" ]]; then
    printf 'comment_keep_list\tinvalid\tuserConfig: %s (%s)\n' "$keep_list" "$1"
    exit 0
  fi
  for key in "${KEYS[@]}"; do printf '%s\tunset\t%s\n' "$key" "$1"; done
  exit 0
}

if ! root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$root" ]]; then
  unset_all "not in a git working tree"
fi
home="$(cd "$HOME" 2>/dev/null && pwd -P)" || home="$HOME"
if [[ "$home" == "$root" || "$home" == "${root%/}/"* ]]; then
  unset_all "repository root is \$HOME or an ancestor of it"
fi

if [[ -n "$keep_list" ]]; then
  if valid comment_keep_list "$keep_list"; then
    printf 'comment_keep_list\t%s\tuserConfig\n' "$keep_list"
  else
    printf 'comment_keep_list\tinvalid\tuserConfig: %s\n' "$keep_list"
  fi
  exit 0
fi

conventions="$("$BASH" "$LIB/resolve-convention-home.sh" --root "$root" 2>/dev/null)"
case $? in
0) ;;
1 | 4) conventions=docs/conventions ;;
3) unset_all "the convention-home pointer is broken" ;;
*) unset_all "the convention home does not apply" ;;
esac
TEAM="$conventions/code-tidying.yaml"
PERSONAL="$conventions/code-tidying.local.yaml"

if [[ -n "$list_key" ]]; then
  [[ -f "$root/$TEAM" ]] || exit 0
  "$BASH" "$READER" --strict --list "$root/$TEAM" "$list_key" 2>/dev/null
  if (($? == 3)); then
    printf 'comment-settings: %s does not parse; %s read as empty\n' "$TEAM" "$list_key" >&2
  fi
  exit 0
fi

read_layer() {
  local file="$root/$1" key="$2" count value
  val=""
  bad=""
  [[ -f "$file" ]] || return 0
  count="$(grep -cE "^[\"']?${key}[\"']?[[:space:]]*:" "$file")"
  if [[ "$count" =~ ^[0-9]+$ ]] && ((count > 1)); then
    bad="set $count times"
    return 0
  fi
  value="$("$BASH" "$READER" --strict "$file" "$key" 2>/dev/null)"
  if (($? == 3)); then
    bad="does not parse"
    return 0
  fi
  [[ -z "$value" ]] && return 0
  if valid "$key" "$value"; then
    val="$value"
  else
    bad="$value"
  fi
}

for key in "${KEYS[@]}"; do
  winner=""
  from=""
  layers=("$TEAM" "$PERSONAL")
  where="$TEAM or $PERSONAL"
  if [[ "$TEAM_ONLY_KEYS" == *" $key "* ]]; then
    layers=("$TEAM")
    where="$TEAM"
  fi
  for layer in "${layers[@]}"; do
    read_layer "$layer" "$key"
    if [[ -n "$bad" ]]; then
      printf '%s\tinvalid\t%s: %s\n' "$key" "$layer" "$bad"
    elif [[ -n "$val" ]]; then
      winner="$val"
      from="$layer"
    fi
  done
  if [[ -n "$winner" ]]; then
    printf '%s\t%s\t%s\n' "$key" "$winner" "$from"
  else
    printf '%s\tunset\tno valid value in %s\n' "$key" "$where"
  fi
done
