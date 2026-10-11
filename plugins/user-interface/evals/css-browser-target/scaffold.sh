#!/usr/bin/env bash
# Seeds an app whose browserslist target predates several modern CSS features.
set -euo pipefail

mkdir -p src
cat > package.json <<'JSON'
{ "name": "helpdesk", "private": true }
JSON
cat > .browserslistrc <<'TXT'
safari >= 15
chrome >= 109
firefox >= 115
TXT
cat > src/app.css <<'CSS'
.help-button { padding: 0.5rem 0.75rem; }
CSS
