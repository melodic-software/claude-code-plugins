#!/usr/bin/env bash
# Seeds a small app with a token file.
set -euo pipefail

mkdir -p src/styles
cat > package.json <<'JSON'
{ "name": "fieldnotes", "private": true }
JSON
cat > src/styles/tokens.css <<'CSS'
:root {
  --color-surface: oklch(98% 0.01 250);
  --color-text: oklch(25% 0.02 250);
  --color-accent: oklch(55% 0.18 250);
  --color-danger: oklch(55% 0.2 25);
  --color-danger-surface: oklch(95% 0.03 25);
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --radius-md: 0.5rem;
  --ease-out: cubic-bezier(0.23, 1, 0.32, 1);
  --duration-fast: 150ms;
}
CSS
cat > src/styles/app.css <<'CSS'
@import "./tokens.css";

body { color: var(--color-text); background: var(--color-surface); }
.card { padding: var(--space-4); border-radius: var(--radius-md); }
CSS
