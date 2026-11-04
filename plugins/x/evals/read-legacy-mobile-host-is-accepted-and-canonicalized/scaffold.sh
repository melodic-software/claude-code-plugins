#!/usr/bin/env bash
# A saved xtomd conversion in the JSON form ({markdown, url, author}) of x.com/jack/status/20, whose
# converter-echoed url keeps the legacy mobile.twitter.com host: the decoy an attribution must not copy.
set -euo pipefail
mkdir -p notes
cat >notes/xtomd-20.json <<'JSON'
{
  "markdown": "**@jack** · 2006-03-21\n\njust setting up my twttr\n",
  "url": "https://mobile.twitter.com/jack/status/20",
  "author": {
    "name": "jack",
    "username": "jack"
  }
}
JSON
