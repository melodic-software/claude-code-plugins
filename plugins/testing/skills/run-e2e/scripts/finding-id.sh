# shellcheck shell=bash
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
