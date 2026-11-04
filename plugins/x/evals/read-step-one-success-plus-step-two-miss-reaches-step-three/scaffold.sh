#!/usr/bin/env bash
# Two saved responses for a chain step 2 cannot recover: the xtomd /api/fetch JSON (SKILL.md Step 1
# names its raw fields: text, rawText, media, quoteTweet, isNoteTweet and engagement counts; the
# author object and the createdAt key are invented for attribution), a chain root with isNoteTweet
# false ending on a 1/ marker; and the Thread Reader App response for the same id, a 200 whose first
# line records a final URL ending in /error (failure-modes.md "Step 2: Thread Reader App miss
# detection"). Every handle, place and post is invented.
set -euo pipefail
mkdir -p notes
cat >notes/x-4444444444444444444-t9.json <<'JSON'
{"url":"https://twitter.com/someone/status/4444444444444444444","author":{"screenName":"someone","name":"Some One"},"createdAt":"2026-10-22T07:45:00Z","text":"Five things we learned running the Ashcombe repair cafe for a year. 1/","rawText":"Five things we learned running the Ashcombe repair cafe for a year. 1/","isNoteTweet":false,"media":[],"quoteTweet":null,"replies":12,"retweets":30,"likes":188}
JSON
cat >notes/threadreader-4444444444444444444.html <<'HTML'
<!-- final URL: https://threadreaderapp.com/thread/4444444444444444444/error (HTTP 200) -->
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Thread Reader App</title></head>
<body><p>Sorry, we could not find this thread. It may not have been unrolled yet.</p></body>
</html>
HTML
