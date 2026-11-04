#!/usr/bin/env bash
# A saved xtomd /api/fetch result for a short chain root (isNoteTweet false, ends with a 1/ marker)
# and the Thread Reader App page for its id, saved in wget's host/path layout: HTTP 200, but the
# final URL ends in /error and the page carries no posts.
set -euo pipefail
mkdir -p notes/threadreaderapp.com/thread
cat >notes/xtomd-fetch-4444444444444444444.json <<'JSON'
{
  "id": "4444444444444444444",
  "author": {
    "name": "Quayside Tide Watch",
    "username": "fakehandle"
  },
  "createdAt": "2026-11-02T12:30:08.000Z",
  "isNoteTweet": false,
  "text": "We rebuilt the whole tide-gauge network this summer: six sites, three new sensors, one very wet August. What worked, what didn't, and what it cost 🧵 1/",
  "rawText": "We rebuilt the whole tide-gauge network this summer: six sites, three new sensors, one very wet August. What worked, what didn't, and what it cost 🧵 1/",
  "media": [],
  "quoteTweet": null,
  "replies": 7,
  "retweets": 15,
  "likes": 233
}
JSON
cat >notes/threadreaderapp.com/thread/4444444444444444444.txt <<'TXT'
final URL: https://threadreaderapp.com/thread/4444444444444444444/error
HTTP status: 200
TXT
cat >notes/threadreaderapp.com/thread/4444444444444444444.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Thread Reader App</title>
</head>
<body>
<div class="container">
<h3>Sorry, we could not find this thread.</h3>
<p>It may not have been unrolled yet, or the tweets may be unavailable.</p>
<p>To unroll a thread, reply to any tweet of the thread with "@threadreaderapp unroll".</p>
</div>
</body>
</html>
HTML
