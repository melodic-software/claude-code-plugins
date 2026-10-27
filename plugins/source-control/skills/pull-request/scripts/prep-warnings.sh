#!/usr/bin/env bash
# prep-warnings.sh — Prep's advisory warnings before the first push: a cut to an
# existing SKILL.md or agent body with no eval change, and a changed path the
# guarded merge holds for a person. Reads the working tree against the merge
# base of --base and HEAD; prep_warnings.py states each rule.
#
# Usage:
#   prep-warnings.sh --base <ref> [--dir <checkout>]
#
# Output, one line per finding, nothing when none:
#   skill-cut <path>: <detail>
#   protected-path <path>: <detail>
#   note: <detail>
#
# merge.diff-check.denied-paths is read from docs/conventions/pr-pipeline.yaml
# at --base, where the guarded merge reads it.
#
# Exit codes:
#   0  read, whatever it found
#   1  invalid argument
#   2  git could not read the base or the diff
#   3  no Python 3.11+ on PATH

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'prep-warnings: %s\n' "$2" >&2
  exit "$1"
}

BASE="" DIR="."
while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --base)
    (($# >= 2)) || die 1 "--base needs a value"
    [[ -n "$2" && "$2" != -* ]] || die 1 "--base must name a ref"
    BASE="$2"
    shift 2
    ;;
  --dir)
    (($# >= 2)) || die 1 "--dir needs a value"
    DIR="$2"
    shift 2
    ;;
  *) die 1 "unknown argument $(printf '%q' "$1") (use --help)" ;;
  esac
done
[[ -n "$BASE" ]] || die 1 "--base is required"
cd "$DIR" 2>/dev/null || die 1 "--dir is not a directory: $DIR"
# Every path the script reads is repository-relative.
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || die 2 "not inside a git checkout: $DIR"
cd "$TOP" || die 2 "cannot enter the checkout's top: $TOP"

SHA="$(git rev-parse --verify --quiet --end-of-options "$BASE^{commit}")" ||
  die 2 "the base does not resolve to a commit: $BASE"

DENIED=()
if paths="$(bash "$SCRIPT_DIR/../../../lib/parse-concern-value.sh" --strict --list --ref "$SHA" \
  docs/conventions/pr-pipeline.yaml merge.diff-check.denied-paths 2>/dev/null)"; then
  while IFS= read -r glob; do
    [[ -z "$glob" ]] || DENIED+=("--denied-path=$glob")
  done <<<"$paths"
else
  printf 'note: docs/conventions/pr-pipeline.yaml at %s could not be read; merge.diff-check.denied-paths not checked\n' "$BASE"
fi

# shellcheck source=../../babysit-prs/scripts/babysit-python.sh
. "$SCRIPT_DIR/../../babysit-prs/scripts/babysit-python.sh"
babysit_python "$SCRIPT_DIR/prep_warnings.py" --base "$SHA" ${DENIED[@]+"${DENIED[@]}"}
