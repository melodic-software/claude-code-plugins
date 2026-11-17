#!/usr/bin/env bash
set -euo pipefail

skill=.claude/skills/control-shop
mkdir -p "$skill/features/cart" src
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

- Cart | features/cart/README.md | entry points: 1 | sources: src/cart.ts
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
cat >src/server.ts <<'TS'
import express from "express";
import { cart } from "./cart";

const app = express();

app.use(express.json());
app.use("/cart", cart);

app.get("/healthz", (_req, res) => res.send("ok"));

// The shop moved off 3000 so it can sit beside the admin console.
app.listen(4100, "127.0.0.1");
TS
: >src/cart.ts
