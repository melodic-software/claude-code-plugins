#!/usr/bin/env bash
# Seeds the eval workspace with a small app that has its own design system.
set -euo pipefail

mkdir -p design docs src
cat > package.json <<'JSON'
{ "name": "ledgerly", "private": true, "dependencies": { "@mui/material": "^6.1.0", "react": "^19.0.0" } }
JSON
cat > design/tokens.json <<'JSON'
{
  "color": { "brand": { "pine": "#0B6E4F" }, "text": { "muted": "#5B6770" }, "surface": { "card": "#F7F5F0" } },
  "space": { "gutter": "18px", "stack": "10px" },
  "radius": { "card": "3px" },
  "font": { "body": "Inter, sans-serif" }
}
JSON
cat > docs/design-system.md <<'MD'
# Ledgerly design system

- Colors, spacing, radius and type come only from `design/tokens.json`. No other values.
- Empty states: one line of text in `color.text.muted`, one secondary button, and no illustration.
- Cards: `surface.card` background, `radius.card` corners, `space.gutter` padding, no shadow.
- Buttons: MUI `Button`; primary actions use `color.brand.pine`, never gradients.
MD
