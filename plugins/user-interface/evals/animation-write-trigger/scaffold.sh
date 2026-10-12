#!/usr/bin/env bash
# Seeds a plain HTML and CSS app with a notification panel that opens without motion.
set -euo pipefail

mkdir -p src
cat > index.html <<'HTML'
<!doctype html>
<html lang="en">
  <head><link rel="stylesheet" href="src/notifications.css"></head>
  <body>
    <aside class="notifications" data-open="false">No new notifications</aside>
  </body>
</html>
HTML
cat > src/notifications.css <<'CSS'
.notifications { position: fixed; inset-block: 0; inset-inline-end: 0; inline-size: 320px; }
.notifications[data-open="false"] { display: none; }
CSS
