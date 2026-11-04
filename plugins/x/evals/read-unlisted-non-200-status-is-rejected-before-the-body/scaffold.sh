#!/usr/bin/env bash
# What a step-1 curl left behind when xtomd answered 307: the spool holds a short text/plain
# "Temporary Redirect" body, and the terminal capture shows -w printing 307 with curl exiting 0,
# because without -L curl does not follow the redirect.
set -euo pipefail
mkdir -p notes
printf 'Temporary Redirect' >notes/x-7777777777777777777-r4.md
cat >notes/x-7777777777777777777-r4.curl.txt <<'TXT'
$ curl -q -sS --proto '=https' --max-time 30 --max-filesize 5000000 -X POST https://xtomd.com/api/markdown -H "Content-Type: application/json" -H "Accept: text/markdown" -d '{"url":"https://x.com/fakehandle/status/7777777777777777777"}' -o 'notes/x-7777777777777777777-r4.md' -w '%{http_code}'
307
$ echo $?
0
TXT
