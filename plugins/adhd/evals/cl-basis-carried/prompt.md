---
description: "Explicit clarify carries each Basis through unchanged: 'none stated' for the item with no basis, 'withheld' with its settling evidence for the open question, and the cited basis verbatim"
tags: [adhd, clarify, outcome, basis]
max_turns: 6
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "D2 shows Basis 'none stated' (no inferred basis); D3 renders as withheld, with the dry run of the rotation on staging as the evidence that would settle it and no invented recommendation; D4 keeps 'legal memo LM-17 §2' verbatim; D1 keeps judgment; the reply closes with the lens line."
---

/adhd:clarify Decisions for the billing rollout:

D1: Rename the `invoice_v2` table to `invoices` during the Sunday window. Basis: judgment.
D2: Switch the webhook signer from HMAC-SHA1 to HMAC-SHA256.
D3: Whether to rotate the production Stripe secret before or after cutover is still open. I am not recommending either yet; a dry run of the rotation on staging would settle it.
D4: Set the invoice PDF retention to 400 days. Basis: legal memo LM-17 §2.
