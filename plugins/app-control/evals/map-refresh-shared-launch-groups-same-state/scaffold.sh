#!/usr/bin/env bash
set -euo pipefail

skill=.claude/skills/control-shop
mkdir -p "$skill/features/cart" "$skill/features/wishlist" "$skill/features/export" src
cat >"$skill/SKILL.md" <<'MD'
---
description: "Launch, ready-check, capture and clean up the shop app."
---

- App: shop, built from `src/`
- Driving tool: playwright

## Launch

Run `npm start` from the repository root and record the pid it prints.

Data: `./data`, a fresh directory per run, migrated and seeded at launch
Side by side: no: the server binds one fixed port

## Ready

`curl -fsS http://127.0.0.1:4100/healthz`

## Capture

none

## Cleanup

Stop the pid recorded at launch.

## Features

- Cart | features/cart/README.md | entry points: 1 | sources: src/cart.ts
- Wishlist | features/wishlist/README.md | entry points: 1 | sources: src/wishlist.ts
- Export | features/export/README.md | entry points: 1 | sources: src/export.ts
MD
for f in cart wishlist export; do
  cat >"$skill/features/$f/README.md" <<MD
# ${f}

## Parts

- ${f}

## Sub-features

none

## Entry points

- the \`${f}\` page: driven

## Reset

Delete \`./data/${f}\` rows and reload the page.

## Drive

- Open \`/${f}\`. Result: the ${f} page shows.
- **Proof.** Result: the ${f} page lists its rows. Captures: screenshot

## Gotchas

none
MD
done
: >src/cart.ts
: >src/wishlist.ts
: >src/export.ts
