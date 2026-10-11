#!/usr/bin/env bash
# Seeds an app whose CSS conventions require physical properties.
set -euo pipefail

mkdir -p docs src/styles
cat > package.json <<'JSON'
{ "name": "ledgerline", "private": true }
JSON
cat > docs/css-conventions.md <<'MD'
# CSS conventions

- This app ships left-to-right only. Write physical properties (`margin-left`, `padding-right`,
  `left`, `right`, `text-align: left`). Do not write logical properties such as
  `margin-inline-start`; our PDF renderer does not support them.
- Spacing values come in multiples of 4px.
MD
cat > src/styles/nav.css <<'CSS'
.nav { display: flex; padding-left: 16px; }
.nav__item { margin-right: 8px; }
CSS
