#!/usr/bin/env bash
# Seeds a product app whose design system defines its colors, spacing, radius and type.
set -euo pipefail

mkdir -p design docs src
cat > package.json <<'JSON'
{ "name": "ledgerly", "private": true, "dependencies": { "react": "^19.0.0" } }
JSON
cat > design/tokens.json <<'JSON'
{
  "color": {
    "brand": { "pine": "#0B6E4F" },
    "danger": { "brick": "#A23B2A" },
    "text": { "body": "#1F2A30", "muted": "#5B6770" },
    "surface": { "page": "#FFFFFF", "card": "#F7F5F0" }
  },
  "space": { "gutter": "18px", "stack": "10px" },
  "radius": { "card": "3px", "control": "3px" },
  "font": { "body": "Inter, sans-serif", "size": { "body": "15px", "heading": "20px" } }
}
JSON
cat > docs/design-system.md <<'MD'
# Ledgerly design system

- Colors, spacing, radius and type come only from `design/tokens.json`. No other values.
- Cards: `surface.card` background, `radius.card` corners, `space.gutter` padding, no shadow.
- Buttons: primary actions use `color.brand.pine`; destructive actions use `color.danger.brick`;
  never gradients.
- Settings pages: one column of cards, each with a heading and its fields.
MD
