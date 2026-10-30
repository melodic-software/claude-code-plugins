#!/usr/bin/env bash
# The fix flow's concurrent-edit guard: record a file's sha256 and check it
# again before each write.
#
#   digest-guard.sh init <run-dir>
#   digest-guard.sh record <absolute file> <run-dir>
#   digest-guard.sh check <absolute file> <run-dir>
#
# init creates the run directory, which must not exist yet. record writes the
# file's digest to <run-dir>/digests/<sha256 of the file's path>.sha256,
# creating both directories when absent. check compares the file's digest with
# the recorded one and prints match or mismatch.
#
# The run directory's name is ai-slop-fix-<TS>, TS as `date -u +%Y%m%dT%H%M%SZ`
# with an optional -<n> suffix, and its parent, symlinks resolved, must sit at
# or under the state root: AI_SLOP_STATE_ROOT when set; else, when this script
# runs from a CI lane's staged copy (<lane>/plugins/ai-slop/skills/audit/scripts),
# the lane's scratch directory <lane>/scratch; else the run directory's parent.
# A rule that allows this script by path accepts any arguments, so the
# confinement sits here.
#
# Exit: 0 recorded, created or matching; 1 mismatch; 2 usage error or refusal.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR_LOGICAL="$(cd -L "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
LANE_SUFFIX=/plugins/ai-slop/skills/audit/scripts

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '/^set -euo/d' -e 's/^# \{0,1\}//' >&2
}

die() {
  echo "digest-guard.sh: $*" >&2
  exit 2
}

sha256_hex() {
  local line
  if command -v sha256sum >/dev/null 2>&1; then
    line="$(sha256sum)" || die "cannot digest"
  else
    line="$(shasum -a 256)" || die "cannot digest"
  fi
  printf '%s' "${line%% *}"
}

# Prints the resolved run directory, refusing any whose parent lies outside the
# state root or whose name is not a run directory's.
resolve_run() {
  local run="$1" name parent root
  name="$(basename -- "$run")"
  [[ "$name" =~ ^ai-slop-fix-[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$ ]] ||
    die "not a run directory name: $name"
  parent="$(cd -P -- "$(dirname -- "$run")" 2>/dev/null && pwd)" ||
    die "the run directory's parent does not exist: $run"
  if [[ -n "${AI_SLOP_STATE_ROOT:-}" ]]; then
    root="$AI_SLOP_STATE_ROOT"
  elif [[ "$SCRIPT_DIR_LOGICAL" == */.lane"$LANE_SUFFIX" ]]; then
    root="${SCRIPT_DIR_LOGICAL%"$LANE_SUFFIX"}/scratch"
  elif [[ "$SCRIPT_DIR" == */.lane"$LANE_SUFFIX" ]]; then
    root="${SCRIPT_DIR%"$LANE_SUFFIX"}/scratch"
  else
    root="$parent"
  fi
  root="$(cd -P -- "$root" 2>/dev/null && pwd)" || die "the state root does not exist: $root"
  [[ "$parent" == "$root" || "$parent" == "${root%/}/"* ]] ||
    die "the run directory is outside the state root $root: $run"
  [[ ! -L "$parent/$name" ]] || die "the run directory is a symbolic link: $parent/$name"
  printf '%s/%s' "${parent%/}" "$name"
}

# Creates a directory, or accepts an existing real one.
ensure_dir() {
  [[ ! -L "$1" ]] || die "a symbolic link stands at $1"
  [[ -d "$1" ]] || mkdir -- "$1" || die "cannot create $1"
}

[[ $# -ge 1 ]] || {
  usage
  exit 2
}
cmd="$1"
shift
case "$cmd" in
init)
  [[ $# -eq 1 ]] || die "init takes one run directory"
  run="$(resolve_run "$1")"
  [[ ! -e "$run" ]] || die "the run directory exists already: $run"
  mkdir -- "$run" || die "cannot create $run"
  printf '%s\n' "$run"
  ;;
record | check)
  [[ $# -eq 2 ]] || die "$cmd takes a file and a run directory"
  file="$1"
  [[ "$file" == /* ]] || die "not an absolute path: $file"
  [[ -f "$file" ]] || die "not a regular file: $file"
  [[ -r "$file" ]] || die "cannot read $file"
  run="$(resolve_run "$2")"
  state="$run/digests/$(printf '%s' "$file" | sha256_hex).sha256"
  digest="$(sha256_hex <"$file")"
  if [[ "$cmd" == record ]]; then
    ensure_dir "$run"
    ensure_dir "$run/digests"
    [[ ! -L "$state" ]] || die "a symbolic link stands at $state"
    tmp="$(mktemp "$run/digests/.tmp.XXXXXX")" || die "cannot write in $run/digests"
    { printf '%s\n' "$digest" >"$tmp" && mv -f -- "$tmp" "$state"; } || {
      rm -f -- "$tmp"
      die "cannot write $state"
    }
  else
    [[ -f "$state" && ! -L "$state" ]] || die "no digest recorded for $file in $run"
    if [[ "$(<"$state")" == "$digest" ]]; then
      echo match
    else
      echo mismatch
      exit 1
    fi
  fi
  ;;
--help | -h)
  usage
  exit 0
  ;;
*)
  usage
  exit 2
  ;;
esac
