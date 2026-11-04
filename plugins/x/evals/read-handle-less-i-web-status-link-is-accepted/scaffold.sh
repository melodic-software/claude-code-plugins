#!/usr/bin/env bash
# A saved xtomd conversion in the JSON form ({markdown, url, author}) of a post reached through a
# handle-less /i/web/status/ link. The body names the author; the converter-echoed url carries a
# handle the input URL never had, the decoy an attribution must not copy.
set -euo pipefail
mkdir -p notes
cat >notes/xtomd-1234567890123456789.json <<'JSON'
{
  "markdown": "**@fakehandle** · 2026-10-30\n\nThe Mill Lane level crossing closes overnight Tuesday to Thursday, 22:00 to 05:00, for resurfacing. Diversion signed via Station Road.\n\nReplies: 3 · Reposts: 9\n",
  "url": "https://x.com/fakehandle/status/1234567890123456789",
  "author": {
    "name": "Mill Lane Works",
    "username": "fakehandle"
  }
}
JSON
