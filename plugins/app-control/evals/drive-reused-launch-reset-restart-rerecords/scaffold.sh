#!/usr/bin/env bash
set -euo pipefail

skill=.claude/skills/control-shop
out=out/grp
mkdir -p "$skill/features/cart" "$skill/features/reviews" src "$out"
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
- Reviews | features/reviews/README.md | entry points: 1 | sources: src/reviews.ts
MD
for f in cart reviews; do
  if [ "$f" = reviews ]; then reset='Delete `./data` and restart the app.'; else reset='Delete `./data/cart` rows and reload the page.'; fi
  cat >"$skill/features/$f/README.md" <<MD
# $f

## Parts

- $f

## Sub-features

none

## Entry points

- the \`$f\` page: driven

## Reset

$reset

## Drive

- Open \`/$f\`. Result: the $f page shows.
- **Proof.** Result: the $f page lists its rows. Captures: screenshot

## Gotchas

none
MD
  : >"src/$f.ts"
done
cat >"$out/report.json" <<'JSON'
{
  "resolved": {"file": "features/cart/README.md", "part": null},
  "mode": "unattended",
  "launch": [
    {
      "app": "shop",
      "pid": 7311,
      "uid": 1000,
      "start_time": 51234,
      "command_line": "node server.js",
      "command_line_sha256": "3f7a9c0e1b2d4f6a8c0e2b4d6f8a0c2e4b6d8f0a2c4e6b8d0f2a4c6e8b0d2f4a"
    }
  ],
  "steps": [
    {
      "action": "Open `/cart`",
      "entry_point": "the `cart` page",
      "stated_result": "the cart page shows",
      "observed": "the cart page shows one empty list",
      "artifacts": []
    }
  ],
  "blocked": [],
  "capability_gaps": [],
  "cleanup": null
}
JSON
