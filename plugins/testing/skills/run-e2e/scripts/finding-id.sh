# shellcheck shell=bash
# Run it with bash, as run-e2e's SKILL.md does. Prints the id of one /testing:run-e2e map finding (../schemas/findings.schema.json):
# the first 16 hex digits of the SHA-256 of feature, part, kind and where, each
# on its own line, the last with no newline after it. The entry point is not
# hashed, so one failure seen through several entry points is one finding, and
# the same failure keeps its id from one pass to the next.
#
#   bash finding-id.sh <feature> <part> <kind> <where>
#
# <part> is "" when the pass drove whole features (part null in findings.json).
# <kind> is result-not-met, error, crash, refusal, no-output or garbled-output;
# <where> is a drive step number, proof or run.
#
# Exit 0 with the id on stdout, 2 on a usage error or when neither sha256sum
# nor shasum is on PATH.
set -uo pipefail

die() {
  echo "finding-id.sh: $1" >&2
  exit 2
}

(($# == 4)) || die "usage: finding-id.sh <feature> <part> <kind> <where>"
feature="$1" part="$2" kind="$3" where="$4"
[[ -n "$feature" && "$feature" != *$'\n'* && "$part" != *$'\n'* ]] ||
  die "feature must be non-empty, and feature and part one line each"
case "$kind" in
result-not-met | error | crash | refusal | no-output | garbled-output) ;;
*) die "unknown kind '$kind'" ;;
esac
[[ "$where" =~ ^([1-9][0-9]*|proof|run)$ ]] || die "where must be a step number, proof or run, not '$where'"

if command -v sha256sum >/dev/null 2>&1; then
  hash=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  hash=(shasum -a 256)
else
  die "sha256sum or shasum is required"
fi

digest="$(printf '%s\n%s\n%s\n%s' "$feature" "$part" "$kind" "$where" | "${hash[@]}")" ||
  die "${hash[0]} failed"
printf '%s\n' "${digest:0:16}"
