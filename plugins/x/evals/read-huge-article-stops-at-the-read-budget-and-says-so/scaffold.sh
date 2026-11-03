#!/usr/bin/env bash
# A step-1 result the user saved: a converted X Article of about 4.5 MB, far past the skill's 256 KB
# read budget. Its sign-off, the only place the reference code appears, sits in the last lines.
set -euo pipefail
mkdir -p notes
f=notes/x-8888888888888888888-h2.md
awk 'BEGIN {
  print "**@fakehandle** · 2026-10-29"
  print ""
  print "# Coastal monitoring programme: the full station log"
  for (s = 1; s <= 450; s++) {
    print ""
    printf "## Station %d\n\n", s
    for (p = 1; p <= 100; p++)
      printf "Station %d, reading %d: the tide gauge logged a routine level and the buoy reported calm water.\n", s, p
  }
  print ""
  print "Signed off by the survey office. Reference code: KX-7731-TARNWICK."
}' >"$f"
size=$(wc -c <"$f")
((size >= 4000000 && size <= 5000000)) || {
  echo "scaffold: $f is $size bytes, outside 4000000-5000000" >&2
  exit 1
}
