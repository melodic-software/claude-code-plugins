#!/usr/bin/env bash
# A saved xtomd /api/fetch result for a long note tweet (isNoteTweet true) that ends with a 1/ marker
# and quotes a post with another id, plus Thread Reader App pages in wget's host/path layout, each
# with its final URL and status beside it: the root id's thread, and a different thread under the
# quoted post's id, so the page a model opens shows which id it used.
set -euo pipefail
mkdir -p notes/threadreaderapp.com/thread
cat >notes/threadreaderapp.com/thread/3333333333333333001.txt <<'TXT'
final URL: https://threadreaderapp.com/thread/3333333333333333001.html
HTTP status: 200
TXT
cat >notes/threadreaderapp.com/thread/3333333333333333001.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Thread by @fakecoastguard on Thread Reader App</title>
<link rel="canonical" href="https://threadreaderapp.com/thread/3333333333333333001.html">
</head>
<body>
<div class="thread-info">Thread by <a href="https://twitter.com/fakecoastguard">@fakecoastguard</a> · Oct 31, 2026 · 2 tweets · 1 min read</div>
<div class="t-main">
<div class="content-tweet" id="tweet_1" data-tweet="3333333333333333001">Quayside lifeboat tasked to a yacht in difficulty off Gull Point. Both crew safe.</div>
<div class="content-tweet" id="tweet_2" data-tweet="3333333333333333002">Reminder before the winter season: file a passage plan and carry a handheld VHF. Dial 999 and ask for the Coastguard.</div>
</div>
<div class="unroll-footer">• • •<br>Missing some Tweet in this thread? You can try to force a refresh</div>
</body>
</html>
HTML
cat >notes/xtomd-fetch-3333333333333333333.json <<'JSON'
{
  "id": "3333333333333333333",
  "author": {
    "name": "Quayside Lifeboat",
    "username": "fakehandle"
  },
  "createdAt": "2026-10-31T07:42:55.000Z",
  "isNoteTweet": true,
  "text": "Saturday's shout, start to finish, because a lot of you asked what the pagers were for at 3 a.m.\n\nAt 02:51 the coastguard asked us to launch to a yacht with a fouled propeller drifting toward the rocks off Gull Point. Wind was force 6 from the south-west, the tide was ebbing, and the yacht had two people aboard, both in lifejackets and both calm on the radio. Our all-weather boat was off the slip at 03:04 with a crew of six.\n\nThe first problem was finding them. Their position was 600 m out, because the plotter on board was showing where they had been ten minutes earlier.\n\n1/",
  "rawText": "Saturday's shout, start to finish, because a lot of you asked what the pagers were for at 3 a.m. At 02:51 the coastguard asked us to launch to a yacht with a fouled propeller drifting toward the rocks off Gull Point. Wind was force 6 from the south-west, the tide was ebbing, and the yacht had two people aboard, both in lifejackets and both calm on the radio. Our all-weather boat was off the slip at 03:04 with a crew of six. The first problem was finding them. Their position was 600 m out, because the plotter on board was showing where they had been ten minutes earlier. 1/",
  "media": [],
  "quoteTweet": {
    "id": "3333333333333333001",
    "author": {
      "name": "HM Coastguard Quayside",
      "username": "fakecoastguard"
    },
    "text": "Quayside lifeboat tasked to a yacht in difficulty off Gull Point. Both crew safe."
  },
  "replies": 41,
  "retweets": 120,
  "likes": 2210
}
JSON
cat >notes/threadreaderapp.com/thread/3333333333333333333.txt <<'TXT'
final URL: https://threadreaderapp.com/thread/3333333333333333333.html
HTTP status: 200
TXT
cat >notes/threadreaderapp.com/thread/3333333333333333333.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Thread by @fakehandle on Thread Reader App</title>
<link rel="canonical" href="https://threadreaderapp.com/thread/3333333333333333333.html">
</head>
<body>
<div class="thread-info">Thread by <a href="https://twitter.com/fakehandle">@fakehandle</a> · Oct 31, 2026 · 3 tweets · 2 min read</div>
<div class="t-main">
<div class="content-tweet" id="tweet_1" data-tweet="3333333333333333333">Saturday's shout, start to finish, because a lot of you asked what the pagers were for at 3 a.m. At 02:51 the coastguard asked us to launch to a yacht with a fouled propeller drifting toward the rocks off Gull Point. Wind was force 6 from the south-west, the tide was ebbing, and the yacht had two people aboard, both in lifejackets and both calm on the radio. Our all-weather boat was off the slip at 03:04 with a crew of six. The first problem was finding them. Their position was 600 m out, because the plotter on board was showing where they had been ten minutes earlier. 1/</div>
<div class="content-tweet" id="tweet_2" data-tweet="3333333333333333334">2/ We found them by their deck light at 03:22, about 300 m from the rocks. Getting a tow line across took three passes in that swell; the third went to the bow cleat and held.</div>
<div class="content-tweet" id="tweet_3" data-tweet="3333333333333333335">3/ Towed into the harbor by 04:40, both sailors cold but unhurt. The lesson for anyone with a plotter: check the GPS fix time, not only the dot. Back on station by 05:15.</div>
</div>
<div class="unroll-footer">• • •<br>Missing some Tweet in this thread? You can try to force a refresh</div>
</body>
</html>
HTML
