#!/usr/bin/env bash
# Detect whether a PR's diff is confined to durably-inert documentation paths, so
# the heavy code lanes can report an HONEST evaluated-and-not-applicable success
# instead of running their full suites on a diff that cannot affect them.
#
#   scripts/check-docs-only.sh <base-ref>
#
# Emits `docs_only=true|false` to $GITHUB_OUTPUT (and stdout). "true" means every
# path changed vs <base-ref> matches an allowlist prefix in
# scripts/docs-only-paths.txt — a small POSITIVE set of paths proven to feed no
# code lane. The allowlist (not a blocklist) is the design's safety property: any
# path NOT on it, including a brand-new code input, forces docs_only=false and the
# full suite runs. See that file for the inertness-proof contract.
#
# This never SKIPS a required job (a skipped required job's result is not
# `success`, which the ci-status aggregate rejects, and GitHub leaves a
# workflow-skipped required check Pending — troubleshooting-required-status-checks).
# The lane still runs and still reports success; only its inner expensive steps
# are gated on this output, with an explicit not-applicable log line.
#
# Fail-closed toward RUNNING the full suite: an unresolvable base ref, a missing
# or empty allowlist, or an empty diff all emit docs_only=false with a stderr
# note — never a skip we cannot justify. Exit status is 0 for the normal has-code
# case (a code PR is not an error) and for every fail-closed path; non-zero only
# on usage error (no base-ref argument) or an unwritable output file.
#
# DOCS_ONLY_ALLOWLIST overrides the allowlist path (test injection).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

emit() {
  printf 'docs_only=%s\n' "$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'docs_only=%s\n' "$1" >>"$GITHUB_OUTPUT"
  fi
}

BASE="${1:?usage: check-docs-only.sh <base-ref>}"
ALLOWLIST="${DOCS_ONLY_ALLOWLIST:-scripts/docs-only-paths.txt}"

if [[ ! -f "$ALLOWLIST" ]]; then
  echo "check-docs-only: allowlist not found ($ALLOWLIST) — running full suite" >&2
  emit false
  exit 0
fi

if ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
  echo "check-docs-only: base ref '$BASE' is not a resolvable commit — running full suite" >&2
  emit false
  exit 0
fi

# Active prefixes: strip inline comments and surrounding blank lines.
mapfile -t prefixes < <(sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$ALLOWLIST" | grep -v '^$')

if [[ ${#prefixes[@]} -eq 0 ]]; then
  echo "check-docs-only: allowlist has no active entries — running full suite" >&2
  emit false
  exit 0
fi

mapfile -t changed < <(git diff --name-only "$BASE")

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "check-docs-only: no changed paths vs '$BASE' — running full suite" >&2
  emit false
  exit 0
fi

for path in "${changed[@]}"; do
  matched=0
  for prefix in "${prefixes[@]}"; do
    if [[ "$path" == "$prefix"* ]]; then
      matched=1
      break
    fi
  done
  if [[ $matched -eq 0 ]]; then
    echo "check-docs-only: '$path' is outside the docs-only allowlist — running full suite" >&2
    emit false
    exit 0
  fi
done

echo "check-docs-only: all ${#changed[@]} changed path(s) within the docs-only allowlist" >&2
emit true
exit 0
