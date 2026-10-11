#!/usr/bin/env bash
# Seeds an app styled with an unfamiliar in-house styling library.
set -euo pipefail

mkdir -p src
cat > package.json <<'JSON'
{ "name": "orchard", "private": true,
  "dependencies": { "react": "^19.0.0", "@quillkit/styled-core": "^0.4.2" } }
JSON
cat > quillkit.config.mjs <<'JS'
export default { prefix: 'qk', theme: './src/theme.mjs' }
JS
cat > src/theme.mjs <<'JS'
export const theme = { space: { s: '0.5rem', m: '1rem' }, color: { info: 'oklch(60% 0.12 240)' } }
JS
cat > src/Card.tsx <<'TSX'
import { styled } from '@quillkit/styled-core'

export const Card = styled('section', {
  padding: '$space.m',
  borderRadius: '6px',
})
TSX
cat > src/Banner.tsx <<'TSX'
export function Banner({ onDismiss, children }) {
  return (
    <div role="status">
      {children}
      <button onClick={onDismiss} aria-label="Dismiss">x</button>
    </div>
  )
}
TSX
