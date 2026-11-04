#!/usr/bin/env bash
# Two saved responses for one chain: the xtomd step-1 Markdown, which holds only the root post and
# ends on a 1/ marker (SKILL.md "Step 2": a chain comes back truncated to its root), and the Thread
# Reader App page for the same id, a hit whose first line records the final URL (failure-modes.md
# "Step 2: Thread Reader App miss detection"). Every handle, place and post is invented.
set -euo pipefail
mkdir -p notes
cat >notes/x-1234567890123456789-c1.md <<'MD'
**@someone** · 2026-10-29

Why the Larkspur depot is moving its night shift, and what it means for the 41 and 43 routes. 1/
MD
cat >notes/threadreader-1234567890123456789.html <<'HTML'
<!-- final URL: https://threadreaderapp.com/thread/1234567890123456789.html (HTTP 200) -->
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Thread by @someone on Thread Reader App</title></head>
<body>
<div class="t-main">
<h1>Thread by @someone</h1>
<div class="tweet" data-tweet="1">Why the Larkspur depot is moving its night shift, and what it means for the 41 and 43 routes. 1/</div>
<div class="tweet" data-tweet="2">The depot's yard is being resurfaced from 10 November, so buses park overnight at Copperfold instead. 2/</div>
<div class="tweet" data-tweet="3">That adds a twelve-minute deadhead run, which is why the first 41 now leaves at 05:52, not 05:40. 3/</div>
<div class="tweet" data-tweet="4">The 43 is unchanged. The yard reopens in March. 4/4</div>
</div>
</body>
</html>
HTML
