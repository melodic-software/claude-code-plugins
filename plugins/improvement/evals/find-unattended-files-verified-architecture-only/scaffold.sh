#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p .work/architecture/improve/main
cat > .work/architecture/improve/main/deepening-candidates-20261118T060000Z.md <<'CANDIDATES'
# Deepening candidates

- mode: unattended
- verification: standard (docs/conventions/architecture.yaml verification at origin/main, commit 4f1c2a9e7b3d5f6081a2c3d4e5f60718293a4b5c)
- threshold: Speculative
- producer: architecture:improve
- source-sha: 4f1c2a9e7b3d5f6081a2c3d4e5f60718293a4b5c

## Collapse the checkout pricing pass-through

- status: proposed
- files: src/checkout.js, src/pricing.js
- dependency-category: in-process
- recommendation: Strong
- size: S: two modules, one pricing call path
- problem: Checkout forwards each pricing call without adding behavior.
- deepening: Two modules wrap one pricing decision, so a reader opens both to follow it.
- shallow-signal: src/checkout.js forwards its pricing arguments to src/pricing.js unmodified.
- signal-verified: true

## Separate stock lookup from reservation

- status: proposed
- files: src/inventory.js
- dependency-category: in-process
- recommendation: Worth exploring
- size: S: one inventory module and its callers
- problem: One module answers stock questions and changes stock.
- deepening: Callers must know the order of two calls the module could hide.
- shallow-signal: src/inventory.js exposes lookup and reserve as separate steps.
- signal-verified: true

## Put the payment client behind a port

- status: proposed
- files: src/checkout.js
- dependency-category: ports-and-adapters
- recommendation: Speculative
- size: M: a new port, its adapter and checkout's call sites
- problem: Checkout builds its payment client inline.
- deepening: A port would have one adapter today.
- shallow-signal: src/checkout.js constructs the client where it is used.
- signal-verified: false

security-defect: withheld
phase-1.5: downgraded=0 dropped=0 corrected=0
top-recommendation: Collapse the checkout pricing pass-through
CANDIDATES
