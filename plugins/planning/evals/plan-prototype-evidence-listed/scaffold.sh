#!/usr/bin/env bash
# A locked Brief for an invoice approval flow, a tier B early-exit design record, and the durable
# notes two /prototype:pressure-test spikes left. The first was pushed: its branch, its commit SHA
# and one point it left unproven (two approvers acting on one invoice at the same moment). The
# second was not: its local path and why it was not pushed (it reads a copy of production
# invoices). The plan should list both in its Prototype evidence section, the second by its local
# path with that not-pushed reason.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p app/invoices tests .work/invoice-approval/design

cat >app/__init__.py <<'PY'
PY

cat >app/invoices/__init__.py <<'PY'
PY

cat >app/invoices/model.py <<'PY'
from dataclasses import dataclass


@dataclass
class Invoice:
    id: int
    total: int
    status: str = "draft"
PY

cat >tests/test_model.py <<'PY'
from app.invoices.model import Invoice


def test_new_invoice_is_draft():
    assert Invoice(id=1, total=100).status == "draft"
PY

cat >.work/invoice-approval/design/design-resolution.md <<'MD'
---
outcome: early-exit
tier: B
reason: one state machine module beside the existing invoice model, settled by the prototype spike
---

Type sketch: `approve(invoice, approver) -> Invoice` and `reject(invoice, approver, reason) -> Invoice`, moving `status` through draft, submitted, approved and rejected.
MD

cat >.work/invoice-approval/prototype-note.md <<'MD'
# Prototype note: invoice approval state machine

Question: does a four-state approval machine (draft, submitted, approved, rejected) cover the
finance team's approval rules?

Answer: yes. Driven by hand through every transition; a rejected invoice returns to draft and can
be submitted again, and an approved invoice accepts no further transition.

Evidence: branch `spike/invoice-approval-states` at commit `9c41e7a2b05d3f68e1a7c4d29b8f0e35a6c71d24`.

Left unproven: what happens when two approvers act on the same invoice at the same moment; the
spike ran one approver at a time.
MD

cat >.work/invoice-approval/prototype-note-approval-log.md <<'MD'
# Prototype note: invoice approval log

Question: can each approval be recorded as one row in an approvals log, without adding columns to
the invoice model?

Answer: yes. An append-only log keyed by invoice id and approver recorded every transition the
spike drove, and the invoice model needed no change.

Evidence: local path `~/spikes/invoice-approval-log`, not pushed: the spike reads a copy of
production invoices.

Left unproven: how the approvals log is migrated onto the live database.
MD

cat >.work/invoice-approval/PLAN.md <<'MD'
## Brief

### TLDR
- An approval state machine for invoices.

### Problem
- Gap: finance approves invoices by email, so nothing records who approved what.
- Who: the finance approvers, on every invoice over the approval limit.
- Evidence: finance team request (rated: stated by the user).

### Goal
Invoices move through draft, submitted, approved and rejected in code, so each approval is recorded.
- Intent (why, in the user's words): "we stop approving invoices over email"
- Vision (where this heads): every finance workflow runs through recorded state changes
- When goals conflict, prefer: the transitions the prototype settled over new ones

### Work size
- Small: two modules and their tests.

### Constraints
- Follow the transitions the prototype spike in .work/invoice-approval/prototype-note.md settled.
- Record approvals the way the spike in .work/invoice-approval/prototype-note-approval-log.md showed.

### Acceptance criteria
- `approve` and `reject` move an invoice only along the transitions the prototype note lists.
- Each `approve` and `reject` call appends one row to the approvals log.
- A unit test covers each transition, the refused ones, and the log row each one writes.

### Captured assumptions
- Quality bar: internal

### Out-of-scope
- Notifying approvers.

### Deferred questions
None.

## Plan
MD

git add .
git commit -q -m "feat: invoice model"
