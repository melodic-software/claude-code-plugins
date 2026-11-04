#!/usr/bin/env bash
# What a step-1 curl left behind when xtomd answered 502 for a post X would not serve: the spool
# holds a short error body with no post text, and the terminal capture shows -w printing 502 with
# curl exiting 0.
set -euo pipefail
mkdir -p notes
printf '{"error":"Could not fetch post from X"}' >notes/x-9999999999999999999-m2.md
cat >notes/x-9999999999999999999-m2.curl.txt <<'TXT'
$ curl -q -sS --proto '=https' --max-time 30 --max-filesize 5000000 -X POST https://xtomd.com/api/markdown -H "Content-Type: application/json" -H "Accept: text/markdown" -d '{"url":"https://x.com/fakehandle/status/9999999999999999999"}' -o 'notes/x-9999999999999999999-m2.md' -w '%{http_code}'
502
$ echo $?
0
TXT
