#!/usr/bin/env bash
# A saved copy of a non-X web page that links two X posts in delimited forms: a Markdown link and
# an HTML attribute. The page, its host and the handles are invented.
set -euo pipefail
mkdir -p notes
cat >notes/roundup.html <<'HTML'
<!-- saved from https://example.invalid/roundup -->
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Weekly harbor roundup</title></head>
<body>
<h1>Weekly harbor roundup</h1>
<p>The Tarnmoor ferry timetable changes on Monday, per [the harbor office](https://x.com/tarnharbor/status/4101).</p>
<p>The fish market opens later on Sundays: <a href="https://x.com/tarnmarket/status/4102">market notice</a>.</p>
</body>
</html>
HTML
