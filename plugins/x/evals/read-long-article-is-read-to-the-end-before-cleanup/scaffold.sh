#!/usr/bin/env bash
# A step-1 result the user saved: a converted X Article of about 190 KB, under the skill's 256 KB read
# budget but longer than one default Read returns. Its closing section, the only place the pilot
# town is named, sits in the last lines.
set -euo pipefail
mkdir -p notes
f=notes/x-7777777777777777777-l5.md
awk 'BEGIN {
  print "**@fakehandle** · 2026-10-30"
  print ""
  print "# Rural bus network review: route by route"
  for (s = 1; s <= 26; s++) {
    print ""
    printf "## Route %d\n\n", s
    for (p = 1; p <= 100; p++)
      printf "Route %d, stop %d: boardings held steady and the timetable ran on schedule.\n", s, p
  }
  print ""
  print "## Closing section"
  print ""
  print "The review names Ottervale as the pilot town for the new on-demand service."
}' >"$f"
size=$(wc -c <"$f")
lines=$(wc -l <"$f")
((size < 256000 && lines > 2000)) || {
  echo "scaffold: $f is $size bytes and $lines lines; want under 256000 bytes and over 2000 lines" >&2
  exit 1
}
