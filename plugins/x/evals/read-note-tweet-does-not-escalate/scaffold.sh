#!/usr/bin/env bash
# Two saved responses for one long note tweet: the xtomd /api/fetch JSON (SKILL.md Step 1 names its
# raw fields: text, rawText, media, quoteTweet, isNoteTweet and engagement counts; the author object
# and the createdAt key are invented for attribution), complete, isNoteTweet true, with no thread
# request, no mid-thought ending and no 1/ markers; and a Thread Reader App page for the same id,
# saved ahead of time, which the skill has no reason to open (SKILL.md Step 2: isNoteTweet true is
# never on its own a reason to escalate). Every handle, place and post is invented.
set -euo pipefail
mkdir -p notes
text='Field report from the Brackwater allotments, end of season. The rainwater butts saved us in August: forty-two plots ran on stored water for nine days while the mains were off. Next year every plot gets a butt, funded from the seed swap. The compost bays need rebuilding before winter, so the work party on the 15th is the priority. Leeks did well, onions did not, and the blight came late enough that most potatoes were already lifted. Thank you to everyone who turned up on the wet Sundays.'
cat >notes/x-2082736455463728191-n5.json <<JSON
{"url":"https://twitter.com/sedgeloft/status/2082736455463728191","author":{"screenName":"sedgeloft","name":"Sedge Loft"},"createdAt":"2026-10-25T18:04:00Z","text":"$text","rawText":"$text","isNoteTweet":true,"media":[],"quoteTweet":null,"replies":9,"retweets":4,"likes":61}
JSON
cat >notes/threadreader-2082736455463728191.html <<'HTML'
<!-- final URL: https://threadreaderapp.com/thread/2082736455463728191/error (HTTP 200) -->
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Thread Reader App</title></head>
<body><p>Sorry, we could not find this thread. It may not have been unrolled yet.</p></body>
</html>
HTML
