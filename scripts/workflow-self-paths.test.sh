#!/usr/bin/env bash
# test-scope: .github/workflows/*
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

refs="$(cd "$ROOT" && awk '
  FNR == 1 { managed = 0 }
  /SYNC-MANAGED FILE/ { managed = 1 }
  managed || /^[[:blank:]]*#/ { next }
  {
    line = $0
    gsub(/\\\./, ".", line)
    while (match(line, /[A-Za-z0-9_.-]*\/?\.github\/workflows\/[A-Za-z0-9_-]+\.ya?ml/)) {
      ref = substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
      if (ref !~ /^\.github\//) {
        # A preceding path segment: another repository unless it is `./`.
        if (ref !~ /^\.\/\.github\//) continue
        sub(/^\.\//, "", ref)
      }
      print FILENAME "\t" ref
    }
  }' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | sort -u)"

if [[ -z "$refs" ]]; then
  fail "no workflow names a workflow file of this repository; the scan read nothing"
fi
while IFS=$'\t' read -r file ref; do
  [[ -n "$ref" ]] || continue
  if [[ -f "$ROOT/$ref" ]]; then
    ok "$file names $ref, which exists"
  else
    fail "$file names $ref, which does not exist (renamed?)"
  fi
done <<<"$refs"

test_harness::report
