#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE"
[[ -f "$LIB/parse-concern-value.sh" ]] || LIB="$HERE/../lib"
READER="$LIB/parse-concern-value.sh"
KEYS=(comment_posture comment_keep_list comment_edit_scope encode_constraints_unattended class_c_max_lines apply_local_renames comment_lint comment_adr_dir)
TEAM_ONLY_KEYS=" comment_lint comment_adr_dir "
LIST_KEYS=" comment_lint_allow comment_lint_exclude comment_lint_keep_opening "
POLICY_KEYS=" comment_posture comment_keep_list class_c_max_lines comment_lint comment_adr_dir comment_lint_allow comment_lint_exclude comment_lint_keep_opening "
POLICY_FILE=comment-policy.yaml
POLICY_PERSONAL_FILE=comment-policy.local.yaml
TEAM_FILE=code-tidying.yaml
PERSONAL_FILE=code-tidying.local.yaml

help() {
  cat <<'EOF'
Read the code-tidying comment settings from the repository's file layers: the team
file and the personal override, the personal override winning key by key. <home> is
the bound convention home (reference/config.md), docs/conventions when none is bound
or it was declined.

The comment policy keys (comment_posture, comment_keep_list, class_c_max_lines,
comment_lint, comment_adr_dir, comment_lint_allow, comment_lint_exclude and
comment_lint_keep_opening) are read from <home>/comment-policy.yaml and its personal
override <home>/comment-policy.local.yaml. When a layer's comment-policy file does not
set a policy key, that layer's code-tidying file is read for it instead, and each
code-tidying file that sets a policy key is named on stderr with the keys to move.
comment_lint, comment_adr_dir and the three lists are read from the team layer only;
code-tidying.local.yaml is named with any of them it sets as keys to delete.
The other keys are read from <home>/code-tidying.yaml and
<home>/code-tidying.local.yaml.

Usage: comment-settings.sh [<dir>]
       comment-settings.sh --keep-list <value>
       comment-settings.sh --list comment_lint_allow|comment_lint_exclude|comment_lint_keep_opening [<dir>]
       comment-settings.sh --files

  <dir>        a directory inside the repository; default: the current directory.
  --keep-list  check one comment_keep_list value from another layer (userConfig)
               against the current directory's repository, printing its key line
               with the layer userConfig, or its invalid line.
  --list       print the team layer's items for a list key, one per line; nothing
               when the key is unset, the file does not parse (named on stderr)
               or the layer does not apply.
  --files      print the names, relative to <home>, of the files a policy key is
               read from, in read order, one per line.

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
  echo "comment-settings: usage: comment-settings.sh [<dir>] | --keep-list <value> | --list comment_lint_allow|comment_lint_exclude|comment_lint_keep_opening [<dir>] | --files" >&2
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
--files)
  (($# == 1)) || usage
  printf '%s\n' "$POLICY_FILE" "$TEAM_FILE" "$POLICY_PERSONAL_FILE" "$PERSONAL_FILE"
  exit 0
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
TEAM="$conventions/$TEAM_FILE"
PERSONAL="$conventions/$PERSONAL_FILE"
POLICY="$conventions/$POLICY_FILE"
POLICY_PERSONAL="$conventions/$POLICY_PERSONAL_FILE"

sets_key() {
  [[ -f "$root/$1" ]] && grep -qE "^[\"']?${2}[\"']?[[:space:]]*:" "$root/$1"
}

layer_for() {
  if sets_key "$1" "$2"; then
    printf '%s' "$1"
  elif [[ "$1" == "$POLICY" ]]; then
    printf '%s' "$TEAM"
  else
    printf '%s' "$PERSONAL"
  fi
}

if [[ -n "$list_key" ]]; then
  file="$(layer_for "$POLICY" "$list_key")"
  [[ -f "$root/$file" ]] || exit 0
  "$BASH" "$READER" --strict --list "$root/$file" "$list_key" 2>/dev/null
  if (($? == 3)); then
    printf 'comment-settings: %s does not parse; %s read as empty\n' "$file" "$list_key" >&2
  fi
  exit 0
fi

warn_moved() {
  local key keys="" dead=""
  for key in $POLICY_KEYS; do
    sets_key "$1" "$key" || continue
    if [[ "$1" == "$PERSONAL" && "$TEAM_ONLY_KEYS$LIST_KEYS" == *" $key "* ]]; then
      dead+="${dead:+, }$key"
    else
      keys+="${keys:+, }$key"
    fi
  done
  [[ -z "$keys" ]] || printf 'comment-settings: %s sets %s; move them to %s\n' "$1" "$keys" "$2" >&2
  [[ -z "$dead" ]] || printf 'comment-settings: %s sets %s, read from the team layer only; delete them\n' "$1" "$dead" >&2
}
warn_moved "$TEAM" "$POLICY"
warn_moved "$PERSONAL" "$POLICY_PERSONAL"

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
  if [[ "$POLICY_KEYS" == *" $key "* ]]; then
    layers=("$(layer_for "$POLICY" "$key")" "$(layer_for "$POLICY_PERSONAL" "$key")")
    where="$POLICY, $POLICY_PERSONAL, $TEAM or $PERSONAL"
  fi
  if [[ "$TEAM_ONLY_KEYS" == *" $key "* ]]; then
    layers=("${layers[0]}")
    where="$POLICY or $TEAM"
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
