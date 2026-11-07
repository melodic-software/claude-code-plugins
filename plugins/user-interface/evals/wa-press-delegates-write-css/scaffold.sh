#!/usr/bin/env bash
# A plain HTML and CSS site with buttons and no press effect.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" styles index.html
mkdir -p styles
cat > index.html <<'HTML'
<!doctype html>
<html lang="en"><head><link rel="stylesheet" href="styles/site.css"></head>
<body><button class="button">Subscribe</button><button class="button">Contact</button></body></html>
HTML
cat > styles/site.css <<'CSS'
.button { padding-block: 8px; padding-inline: 16px; border-radius: 6px; border: 1px solid currentColor; background: none; }
CSS
