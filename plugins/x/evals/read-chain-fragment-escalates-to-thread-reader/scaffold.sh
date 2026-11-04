#!/usr/bin/env bash
# A saved xtomd conversion of a chain root (a 1/ marker, a quoted post with another id) and Thread
# Reader App pages in wget's host/path layout, each with its final URL and status beside it: the
# root id's thread, and a different thread under the quoted post's id, so the page a model opens
# shows which id it used.
set -euo pipefail
mkdir -p notes/threadreaderapp.com/thread
cat >notes/threadreaderapp.com/thread/1234567890123450001.txt <<'TXT'
final URL: https://threadreaderapp.com/thread/1234567890123450001.html
HTTP status: 200
TXT
cat >notes/threadreaderapp.com/thread/1234567890123450001.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Thread by @harbordesk on Thread Reader App</title>
<link rel="canonical" href="https://threadreaderapp.com/thread/1234567890123450001.html">
</head>
<body>
<div class="thread-info">Thread by <a href="https://twitter.com/harbordesk">@harbordesk</a> · Oct 28, 2026 · 2 tweets · 1 min read</div>
<div class="t-main">
<div class="content-tweet" id="tweet_1" data-tweet="1234567890123450001">Booking site is down again, third time this month.</div>
<div class="content-tweet" id="tweet_2" data-tweet="1234567890123450002">Ended up buying a paper ticket at the kiosk. The queue was out the door and the card reader only took cash.</div>
</div>
<div class="unroll-footer">• • •<br>Missing some Tweet in this thread? You can try to force a refresh</div>
</body>
</html>
HTML
cat >notes/xtomd-1234567890123456789.md <<'MD'
**@fakehandle** · 2026-10-29

1/ We moved the Quayside ferry booking site to a new host last weekend. Short version: Saturday's
outage was us, not the payment provider. Here is what happened, in order 🧵

> Quoting **@harbordesk** · https://x.com/harbordesk/status/1234567890123450001
> Booking site is down again, third time this month.

Replies: 18 · Reposts: 4
MD
cat >notes/threadreaderapp.com/thread/1234567890123456789.txt <<'TXT'
final URL: https://threadreaderapp.com/thread/1234567890123456789.html
HTTP status: 200
TXT
cat >notes/threadreaderapp.com/thread/1234567890123456789.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Thread by @fakehandle on Thread Reader App</title>
<link rel="canonical" href="https://threadreaderapp.com/thread/1234567890123456789.html">
</head>
<body>
<div class="thread-info">Thread by <a href="https://twitter.com/fakehandle">@fakehandle</a> · Oct 29, 2026 · 4 tweets · 1 min read</div>
<div class="t-main">
<div class="content-tweet" id="tweet_1" data-tweet="1234567890123456789">1/ We moved the Quayside ferry booking site to a new host last weekend. Short version: Saturday's outage was us, not the payment provider. Here is what happened, in order 🧵</div>
<div class="content-tweet" id="tweet_2" data-tweet="1234567890123456790">2/ The new host's DNS record went live at 09:00, but the old TLS certificate stayed on the load balancer, so every booking page failed its handshake for about four hours.</div>
<div class="content-tweet" id="tweet_3" data-tweet="1234567890123456791">3/ Bookings already paid for were never at risk: the payment provider held them, and all 212 have now been confirmed by email.</div>
<div class="content-tweet" id="tweet_4" data-tweet="1234567890123456792">4/ From now on a certificate check runs before any DNS change goes live. Sorry to everyone who stood at the terminal refreshing a blank page.</div>
</div>
<div class="unroll-footer">• • •<br>Missing some Tweet in this thread? You can try to force a refresh</div>
</body>
</html>
HTML
