# shellcheck shell=bash
# Resolve the review_venue setting: which venue reviews a pull request, read
# before review-venue.sh. Values: auto (the per-lane read of review-venue.sh),
# local (every local review step runs), ci (the CI lanes review, no local
# step runs), both (the local steps run and the CI lanes still count).
#
# Resolution, lowest first, where a later level wins: the default, auto; the
# userConfig value (--user, the substituted ${user_config.review_venue}); the
# top-level review_venue key of docs/conventions/source-control.yaml as the
# pull request's base branch holds it. Parsing is lib/yaml-subset.awk's.
#
# Usage:
#   read-review-venue.sh [--user <value>]
#       no repository level (no file read, or not a repository)
#   read-review-venue.sh [--user <value>] --base <b> --default-branch <d> -
#       the file's text on stdin
#   read-review-venue.sh [--user <value>] --base <b> --default-branch <d> --http-response
#       a `gh api -i` response on stdin: a 200 is read as the file, a 404
#       means no file
#
# The repository level counts only when --base matches --default-branch: any
# other base is a branch the PR's author may have pushed unreviewed. A base
# that does not match, a failed read, a file that does not parse, or input
# holding a NUL byte leaves the repository level unread, with a notice on
# stderr, and resolution goes on to the userConfig level. An empty --user, or
# one still holding a literal ${user_config...} placeholder, is unset.
#
# A value other than auto, local, ci or both at the level that supplied it is
# not used: the venue is auto, with a notice on stderr naming the level.
#
# Output, one tab-separated line:
#   review_venue  <auto|local|ci|both>  <level>
# where <level> is `repository (docs/conventions/source-control.yaml at <base>)`,
# `userConfig`, `default`, or `invalid value at <level> (fell back to auto)`.
# A substituted auto at the userConfig level reports as default.
#
# Exit 0, or 2 for a usage error. It has no #! line and runs through bash, so
# it needs no executable bit.
set -uo pipefail

# shellcheck source=../../../lib/base-file.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)/base-file.sh"
VALUES=" auto local ci both "

usage() {
  echo "read-review-venue: usage: read-review-venue.sh [--user <v>] [--base <b> --default-branch <d> (- | --http-response)]" >&2
  exit 2
}

notice() { printf 'read-review-venue: %s\n' "${1//[[:cntrl:]]/ }" >&2; }

# resolve <value> <level>: print the line for a value one level supplied.
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

# The repository level: resolves to the file's value when the file sets the key.
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
