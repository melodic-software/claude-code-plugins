#!/usr/bin/env bash
# Two saved responses for a chain whose root is a note tweet: the xtomd /api/fetch JSON (SKILL.md
# Step 1 names its raw fields: text, rawText, media, quoteTweet, isNoteTweet and engagement counts;
# the author object and the createdAt key are invented for attribution), isNoteTweet true, a long
# body ending on a 1/ marker; and the Thread Reader App page for the same id, a hit whose first line
# records the final URL (failure-modes.md "Step 2: Thread Reader App miss detection").
# Every handle, place and post is invented.
set -euo pipefail
mkdir -p notes
text='How we rebuilt the Gorsefield lifeboat slipway in eleven weeks, start to finish. The old slipway had been patched for thirty years and the winter storms finally split the lower section, so the station spent the summer launching from the beach with a tractor. This is the whole story, from the survey to the first launch, including the parts that went wrong. 1/'
cat >notes/x-3333333333333333333-n6.json <<JSON
{"url":"https://twitter.com/someone/status/3333333333333333333","author":{"screenName":"someone","name":"Some One"},"createdAt":"2026-10-24T09:12:00Z","text":"$text","rawText":"$text","isNoteTweet":true,"media":[],"quoteTweet":null,"replies":23,"retweets":17,"likes":240}
JSON
cat >notes/threadreader-3333333333333333333.html <<'HTML'
<!-- final URL: https://threadreaderapp.com/thread/3333333333333333333.html (HTTP 200) -->
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Thread by @someone on Thread Reader App</title></head>
<body>
<div class="t-main">
<h1>Thread by @someone</h1>
<div class="tweet" data-tweet="1">How we rebuilt the Gorsefield lifeboat slipway in eleven weeks, start to finish. 1/</div>
<div class="tweet" data-tweet="2">The survey found the piles sound, so only the deck and the lower apron needed replacing. 2/</div>
<div class="tweet" data-tweet="3">We poured the apron in four tides, using a cofferdam borrowed from the Thornmouth harbor board. 3/</div>
<div class="tweet" data-tweet="4">The first launch off the new slipway was on 3 October, with the whole village on the harbor wall. 4/4</div>
</div>
</body>
</html>
HTML
