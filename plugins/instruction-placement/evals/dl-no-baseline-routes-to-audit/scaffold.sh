#!/usr/bin/env bash
# A committed repository with a CLAUDE.md that was never audited: no spine baseline, no findings artifact.
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p web/src
cat >CLAUDE.md <<'MD'
# Storefront

Run `npm run check` before every commit.

## React components

When you edit a `.tsx` file, keep each component in its own file, type its props with an
interface named `<Component>Props`, and never use default exports.
MD
printf 'export function Cart(): JSX.Element {\n  return <div />;\n}\n' >web/src/Cart.tsx
git add -A
git -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q -m "storefront"
