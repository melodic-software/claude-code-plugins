#!/usr/bin/env bash
# Seeds a stylesheet with known problems, a convention that keeps hex colors, and a Stylelint config.
set -euo pipefail

mkdir -p docs src
cat > package.json <<'JSON'
{ "name": "tidepool", "private": true, "devDependencies": { "stylelint": "^16.0.0" } }
JSON
cat > .stylelintrc.json <<'JSON'
{ "rules": { "color-hex-length": "long", "declaration-no-important": true } }
JSON
cat > docs/css-conventions.md <<'MD'
# CSS conventions

- Colors are hex values in `:root` custom properties, exported from our design tool. Do not convert
  them to `oklch()`.
MD
cat > src/app.css <<'CSS'
:root {
  --brand: #1f6feb;
  --ink: #1b1f24;
}

.button {
  color: var(--ink);
  background: var(--brand);
  margin-left: 8px;
  transition: all 400ms ease-in;
}

.button:hover {
  background: #174ea6;
}

.button:focus {
  outline: none;
}
CSS
