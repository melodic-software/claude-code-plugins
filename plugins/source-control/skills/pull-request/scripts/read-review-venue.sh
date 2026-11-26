# shellcheck shell=bash
set -uo pipefail

# shellcheck source=../../../lib/base-file.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)/base-file.sh"
VALUES=" auto local ci both "

usage() {
  echo "read-review-venue: usage: read-review-venue.sh [--user <v>] [--base <b> --default-branch <d> (- | --http-response)]" >&2
  exit 2
}

notice() { printf 'read-review-venue: %s\n' "${1//[[:cntrl:]]/ }" >&2; }

resolve() {
  if [[ "$VALUES" == *" $1 "* ]]; then
    printf 'review_venue\t%s\t%s\n' "$1" "$2"
  else
    notice "review_venue '$1' at $2 is not auto, local, ci or both; using auto"
    printf 'review_venue\tauto\tinvalid value at %s (fell back to auto)\n' "$2"
  fi
  exit 0
}

mode="" base="" default="" user="" has_base=0 has_default=0
while (($#)); do
  case "$1" in
  --user | --base | --default-branch)
    (($# >= 2)) || usage
    case "$1" in
    --user) user="$2" ;;
    --base) base="$2" has_base=1 ;;
    *) default="$2" has_default=1 ;;
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
if [[ -n "$mode" ]]; then
  ((has_base && has_default)) || usage
elif ((has_base || has_default)); then
  usage
fi

read_repo() {
  [[ -n "$base" ]] || { notice "the pull request's base branch could not be read; the repository level is unread"; return; }
  [[ -n "$default" ]] || { notice "the base repository's default branch could not be read; the repository level is unread"; return; }
  [[ "$base" == "$default" ]] || { notice "base $base is not the default branch $default; the repository level is unread"; return; }

  base_file_read_key "$mode" review_venue
  if [[ "$BASE_FILE_STATE" == failed ]]; then
    notice "$BASE_FILE_REASON; the repository level is unread"
    return
  fi
  ((BASE_FILE_HAS)) && resolve "$BASE_FILE_VALUE" "repository (docs/conventions/source-control.yaml at $base)"
}

[[ -z "$mode" ]] || read_repo

# shellcheck disable=SC2016 # the literal, unsubstituted placeholder
[[ "$user" == *'${user_config'* ]] && user=""
[[ -z "$user" || "$user" == auto ]] && resolve auto default
resolve "$user" userConfig
