#!/usr/bin/env bash
# Read which audit `/source-control:pull-request prep` runs for each change
# class, from the `prep_audits` list in docs/conventions/source-control.yaml as
# the base branch holds it. Each item is a mapping
# `{class: <name>, enabled: true|false, skill: /<plugin>:<skill>}`, `skill`
# optional; a class the list does not name runs its default audit. Parsing is
# lib/yaml-subset.awk's; the reader is at least as strict as
# schemas/source-control.schema.json.
#
# Usage:
#   read-prep-audits.sh --base <b> --default-branch <d> -
#       the file's text on stdin, as `git show <remote>/<d>:<path>` prints it
#
# --base is the branch the pull request will target and --default-branch the
# repository's default branch. The list is honored only when the two match: any
# other base is a branch the author may have pushed unreviewed. There is no
# file-path form: the head branch must not choose its own audits.
#
# Output, tab-separated. First a source line:
#   source  default                 no file, no prep_audits key, or an empty list
#   source  config                  the list was read
#   source  fail-closed  <reason>   the list cannot be trusted
# Then one line per class, in this order: markdown renames skills rules tests.
#   <class>  default                its built-in audit
#   <class>  off                    no audit
#   <class>  replace  <skill>       the named skill in place of the built-in one
# Under default and fail-closed every class is `default`.
#
# Exit 0, or 2 for a usage error.
set -uo pipefail

# shellcheck source=../../../lib/base-file.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)/base-file.sh"

CLASSES=(markdown renames skills rules tests)
# tests is off-only: its judge verdicts feed prep's step 1.3.
REPLACEABLE=" markdown renames skills rules "
SKILL_RE='^/[a-z0-9]+(-[a-z0-9]+)*(:[a-z0-9]+(-[a-z0-9]+)*)?$'
# Fresh arrays, so nothing inherited from the environment reads as a setting.
unset AUDIT ITEM
declare -A AUDIT=() ITEM=()

usage() {
  echo "read-prep-audits: usage: read-prep-audits.sh --base <b> --default-branch <d> -" >&2
  exit 2
}

emit() {
  local source="$1" class
  printf 'source\t%s\n' "$source"
  for class in "${CLASSES[@]}"; do
    printf '%s\t%s\n' "$class" "${AUDIT[$class]:-default}"
  done
  exit 0
}

# The reason can quote the file, so control characters become spaces.
fail_closed() {
  AUDIT=()
  emit "fail-closed"$'\t'"${1//[[:cntrl:]]/ }"
}

base="" default="" has_base=0 has_default=0 has_stdin=0
while (($#)); do
  case "$1" in
  --base | --default-branch)
    (($# >= 2)) || usage
    if [[ "$1" == --base ]]; then base="$2" has_base=1; else default="$2" has_default=1; fi
    shift
    ;;
  -) has_stdin=1 ;;
  *) usage ;;
  esac
  shift
done
((has_base && has_default && has_stdin)) || usage

[[ -n "$base" ]] || fail_closed "the pull request's base branch could not be read"
[[ -n "$default" ]] || fail_closed "the repository's default branch could not be read"
[[ "$base" == "$default" ]] || fail_closed "base $base is not the default branch $default"

base_file_load -
[[ "$BASE_FILE_STATE" == ok ]] || fail_closed "$BASE_FILE_REASON"
doc="$BASE_FILE_DOC"

q="[\"']?"
(($(grep -cE "^[[:space:]]*${q}prep_audits${q}[[:space:]]*:" <<<"$doc") <= 1)) ||
  fail_closed "prep_audits appears more than once"

base_file_records || fail_closed "$BASE_FILE_REASON"

seen=$'\n' max=-1
while IFS=$'\t' read -r key val; do
  case "$key" in prep_audits | prep_audits.*) ;; *) continue ;; esac
  [[ "$key" != prep_audits ]] || fail_closed "prep_audits is not a list"
  rest="${key#prep_audits.}"
  idx="${rest%%.*}"
  [[ "$idx" =~ ^[0-9]+$ ]] || fail_closed "prep_audits is a mapping, not a list"
  [[ "$rest" != "$idx" ]] || fail_closed "prep_audits item $idx is not a {class, enabled} mapping"
  sub="${rest#"$idx".}"
  top="${sub%%.*}"
  [[ ! "$top" =~ ^[0-9]+$ ]] || fail_closed "prep_audits item $idx is not a {class, enabled} mapping"
  case "$sub" in
  class | enabled | skill) ;;
  *)
    case "$top" in
    class | enabled | skill) fail_closed "prep_audits item $idx's $top is not a single value" ;;
    *) fail_closed "prep_audits item $idx has an unknown key '$top'" ;;
    esac
    ;;
  esac
  [[ "$seen" != *$'\n'"$key"$'\n'* ]] || fail_closed "prep_audits item $idx repeats a key"
  seen+="$key"$'\n'
  ITEM["$idx.$sub"]="$val"
  ((idx <= max)) || max=$idx
done <<<"$BASE_FILE_RECORDS"

base_file_list_check prep_audits || fail_closed "$BASE_FILE_REASON"

((max >= 0)) || emit default

# The parser drops quoting, so a quoted enabled is found in the key's own lines.
grep -qE "(^|[[:space:]{,-])${q}enabled${q}[[:space:]]*:[[:space:]]*[\"']" <<<"$BASE_FILE_BLOCK" &&
  fail_closed "an enabled value in prep_audits is quoted, not a boolean"

classes_seen=" "
for ((i = 0; i <= max; i++)); do
  class="${ITEM["$i.class"]:-}" enabled="${ITEM["$i.enabled"]:-}"
  [[ -n "$class" ]] || fail_closed "prep_audits item $i has no class"
  [[ " ${CLASSES[*]} " == *" $class "* ]] || fail_closed "unknown class '$class' in prep_audits"
  [[ "$classes_seen" != *" $class "* ]] || fail_closed "class '$class' is listed twice in prep_audits"
  classes_seen+="$class "
  case "$enabled" in
  true | false) ;;
  '') fail_closed "class '$class' has no enabled value in prep_audits" ;;
  *) fail_closed "class '$class' has enabled '$enabled', not true or false" ;;
  esac
  if [[ -n "${ITEM["$i.skill"]+set}" ]]; then
    skill="${ITEM["$i.skill"]}"
    [[ "$REPLACEABLE" == *" $class "* ]] || fail_closed "class '$class' cannot be replaced, only turned off"
    [[ "$enabled" == true ]] || fail_closed "class '$class' is off and also names a skill"
    [[ "$skill" =~ $SKILL_RE ]] || fail_closed "class '$class' has skill '$skill', not /<plugin>:<skill> or /<skill>"
    AUDIT[$class]="replace"$'\t'"$skill"
  elif [[ "$enabled" == false ]]; then
    AUDIT[$class]=off
  fi
done

emit config
