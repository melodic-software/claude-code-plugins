#!/usr/bin/env bash
# An app with motion defects beside color, typography, layering and alt-text defects.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src index.html
mkdir -p src/components src/pages
cat > index.html <<'HTML'
<!doctype html>
<html lang="en"><head><link rel="stylesheet" href="src/components/card.css"><link rel="stylesheet" href="src/components/modal.css"></head><body></body></html>
HTML
cat > src/components/card.css <<'CSS'
.card { color: #aaa; background: #fff; font-size: 11px; }
.card { transition: all 600ms ease-in; }
.card:hover { transform: scale(1.1); }
CSS
cat > src/components/modal.css <<'CSS'
.modal { z-index: 9999; transform: scale(0); transition: transform 800ms ease-in; }
.modal[open] { transform: scale(1); }
.backdrop { opacity: 0; transition: opacity 200ms; }
.backdrop[data-open] { opacity: 1; }
CSS
cat > src/pages/list.html <<'HTML'
<ul class="list"><li><img src="avatar.png"> Ada</li></ul>
HTML
