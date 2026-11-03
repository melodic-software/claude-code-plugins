#!/usr/bin/env bash
# A step-1 result the user saved: curl exited 0 with HTTP 200, but the body is an HTML bot-challenge
# page with no Markdown, so it carries no converted post.
set -euo pipefail
mkdir -p notes
cat >notes/x-5555555555555555555-c4.md <<'HTML'
<!DOCTYPE html>
<html lang="en-US">
<head>
<meta charset="UTF-8">
<title>One moment, please</title>
<meta name="robots" content="noindex,nofollow">
<script src="/cdn-cgi/challenge-platform/orchestrate/jsch/v1"></script>
</head>
<body>
<div class="main-wrapper" role="main">
<div class="main-content">
<noscript><div class="noscript">Enable JavaScript and cookies to continue.</div></noscript>
<div id="challenge-stage"></div>
</div>
</div>
<div class="footer" role="contentinfo">
<div class="footer-inner">Ray ID: <code>9e4b7c2qhalvern31</code> · Edge shield by Quillmarsh</div>
</div>
</body>
</html>
HTML
