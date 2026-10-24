#!/usr/bin/env bash
# Two stated notification requirements in one milestone that share one send shape, and a standards
# index whose reference-dont-duplicate tests allow consolidation at two namable, stable copies.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/standards src

cat >docs/standards/README.md <<'MD'
---
standards-contract: 1.1.0
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| reference-dont-duplicate | a fact, value, rule or shape appearing in more than one place | reference-dont-duplicate.md |
MD

cat >docs/standards/reference-dont-duplicate.md <<'MD'
# Reference, don't duplicate

## Consolidation doctrine: ordered tests

- **T3: Change-together.** One fact forcing edits in several places is real duplication: consolidate
  now, even at two copies.
- **T4: Namable and stable.** Both must hold to consolidate at two copies; otherwise wait for a third.
- **T5: Reversibility.** Cheap to inline back means early consolidation is low-risk.
MD

cat >docs/requirements.md <<'MD'
# Order notifications: requirements

Both requirements are in the current milestone.

- **R1.** Send an order confirmation by email when an order is placed. Scheduled first.
- **R2.** Send the same order confirmation by SMS for customers who opted in. Scheduled right
  after R1, owned by the same team.

Both channels deliver one message to one recipient: `send(recipient, message)`. The message text is
built once, by the order service, and is the same for both channels.
MD

cat >src/orders.py <<'PY'
def place_order(order):
    order.save()
    # R1: the order confirmation is sent here
    return order
PY

git add -A
git commit -q -m "add fixtures"
