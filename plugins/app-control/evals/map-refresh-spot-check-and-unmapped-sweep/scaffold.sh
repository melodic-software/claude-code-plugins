#!/usr/bin/env bash
set -euo pipefail

skill=.claude/skills/control-shop
mkdir -p "$skill/features/cart" src/routes
cat >"$skill/SKILL.md" <<'MD'
---
description: "Launch, ready-check, capture and clean up the shop app."
---

- App: shop, built from `src/`
- Driving tool: playwright

## Launch

Run `npm start` from the repository root and record the pid it prints.

Data: `./data`, a fresh directory per run
Side by side: no: the server binds one fixed port

## Ready

`curl -fsS http://127.0.0.1:4100/healthz`

## Capture

none

## Cleanup

Stop the pid recorded at launch.

## Features

- Cart | features/cart/README.md | entry points: 1 | sources: src/cart.tsx
MD
cat >"$skill/features/cart/README.md" <<'MD'
# Cart

## Parts

- cart: the items a buyer has picked

## Sub-features

none

## Entry points

- the `Add to cart` button: driven

## Reset

Delete `./data` and restart the app.

## Drive

- Open `/`, choose `Add to cart`. Result: the cart badge reads 1.
- **Proof.** Result: the cart page lists one item. Captures: screenshot

## Gotchas

none
MD
cat >src/cart.tsx <<'TSX'
import { useState } from "react";

type Item = { id: string; name: string };

export function CartButton({ item }: { item: Item }) {
  const [count, setCount] = useState(0);

  function add() {
    setCount(count + 1);
  }

  return (
    <button onClick={add} data-count={count}>
      Add to cart
    </button>
  );
}
TSX
cat >src/routes/returns.ts <<'TS'
import { Router } from "express";

export const returns = Router();

returns.get("/returns", (_req, res) => res.render("returns"));
TS
