#!/usr/bin/env bash
# Exit 0, or 2 for a usage error.

# portability-scope: the GitHub implementation of the base read under --repo; the other forms read stdin.
set -uo pipefail

# shellcheck source=pre-ready-steps.sh
source "$(dirname "${BASH_SOURCE[0]}")/pre-ready-steps.sh"
# shellcheck source=../../../lib/base-file.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)/base-file.sh"

usage() {
  echo "read-pre-ready: usage: read-pre-ready.sh --repo <owner/repo> --base <b>, or --base <b> --default-branch <d> (- | --http-response)" >&2
  exit 2
}

emit() {
  local source="$1" off="$2" step
  printf 'source\t%s\n' "$source"
  for step in "${PRE_READY_STEPS[@]}"; do
    if [[ "$off" == *" $step "* ]]; then
      printf '%s\tdisabled\n' "$step"
    else
      printf '%s\tenabled\n' "$step"
    fi
  done
  exit 0
}

fail_closed() { emit "fail-closed"$'\t'"${1//[[:cntrl:]]/ }" " "; }

mode="" base="" default="" repo="" has_base=0 has_default=0
while (($#)); do
  case "$1" in
  --base | --default-branch | --repo)
    (($# >= 2)) || usage
    case "$1" in
    --base) base="$2" has_base=1 ;;
    --default-branch) default="$2" has_default=1 ;;
    *)
      [[ -z "$mode" ]] || usage
      mode=--repo repo="$2"
      ;;
    esac
    shift
    ;;
  - | --http-response)
    [[ -z "$mode" ]] || usage
    mode="$1"
    ;;
  *) usage ;;
  esac
  shift
done
if [[ "$mode" == --repo ]]; then
  ((has_base && !has_default)) || usage
  [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ && "$repo" != *..* ]] || usage
  default=$(gh api "repos/$repo" --jq '.default_branch' 2>/dev/null) || default=""
else
  ((has_base && has_default)) && [[ -n "$mode" ]] || usage
fi

[[ -n "$base" ]] || fail_closed "the pull request's base branch could not be read"
[[ -n "$default" ]] || fail_closed "the base repository's default branch could not be read"
[[ "$base" == "$default" ]] || fail_closed "base $base is not the default branch $default"

if [[ "$mode" == --repo ]]; then
  base_file_load --http-response < <(gh api -i -X GET "repos/$repo/contents/$CONVENTION_KEY_YAML_REL" \
    -f ref="$base" -H "Accept: application/vnd.github.raw" 2>/dev/null)
else
  base_file_load "$mode"
fi
case "$BASE_FILE_STATE" in
absent) emit default " " ;;
failed) fail_closed "$BASE_FILE_REASON" ;;
*) doc="$BASE_FILE_DOC" ;;
esac

q="[\"']?"
(($(grep -cE "^[[:space:]]*${q}pre_ready${q}[[:space:]]*:" <<<"$doc") <= 1)) ||
  fail_closed "pre_ready appears more than once"

base_file_records || fail_closed "$BASE_FILE_REASON"

unset ITEM
declare -A ITEM=()
seen=$'\n' max=-1
while IFS=$'\t' read -r key val; do
  case "$key" in pre_ready | pre_ready.*) ;; *) continue ;; esac
  [[ "$key" != pre_ready ]] || fail_closed "pre_ready is not a list"
  rest="${key#pre_ready.}"
  idx="${rest%%.*}"
  [[ "$idx" =~ ^[0-9]+$ ]] || fail_closed "pre_ready is a mapping, not a list"
  [[ "$rest" != "$idx" ]] || fail_closed "pre_ready item $idx is not a {step, enabled} mapping"
  sub="${rest#"$idx".}"
  top="${sub%%.*}"
  [[ ! "$top" =~ ^[0-9]+$ ]] || fail_closed "pre_ready item $idx is not a {step, enabled} mapping"
  if [[ "$sub" != step && "$sub" != enabled ]]; then
    [[ "$top" != step && "$top" != enabled ]] || fail_closed "pre_ready item $idx's $top is not a single value"
    fail_closed "pre_ready item $idx has an unknown key '$top'"
  fi
  [[ "$seen" != *$'\n'"$key"$'\n'* ]] || fail_closed "pre_ready item $idx repeats a key"
  seen+="$key"$'\n'
  ITEM["$idx.$sub"]="$val"
  ((idx <= max)) || max=$idx
done <<<"$BASE_FILE_RECORDS"

base_file_list_check pre_ready || fail_closed "$BASE_FILE_REASON"

((max >= 0)) || emit default " "

grep -qE "(^|[[:space:]{,-])${q}enabled${q}[[:space:]]*:[[:space:]]*[\"']" <<<"$doc" &&
  fail_closed "an enabled value in pre_ready is quoted, not a boolean"

off=" " steps_seen=" "
for ((i = 0; i <= max; i++)); do
  step="${ITEM["$i.step"]:-}" enabled="${ITEM["$i.enabled"]:-}"
  [[ -n "$step" ]] || fail_closed "pre_ready item $i has no step"
  [[ " ${PRE_READY_STEPS[*]} " == *" $step "* ]] || fail_closed "unknown step '$step' in pre_ready"
  [[ "$steps_seen" != *" $step "* ]] || fail_closed "step '$step' is listed twice in pre_ready"
  steps_seen+="$step "
  case "$enabled" in
  true) ;;
  false) off+="$step " ;;
  '') fail_closed "step '$step' has no enabled value in pre_ready" ;;
  *) fail_closed "step '$step' has enabled '$enabled', not true or false" ;;
  esac
done

emit config "$off"
