---
outcome: early-exit
tier: B
reason: Third lane of an existing method whose lane contract is already fixed; one new non-spine field and five enum values are the only type-level additions
---

Design gate for topic `justify-existence`, evaluated by `/planning:plan` on 2026-09-05 and
early-exited with the operator's explicit acceptance (Open Decision OD3, "approved").

## Why early-exit is proportionate

The deliverable is `/overengineering:justify`, a third lane skill composing the scrutiny method in
`plugins/overengineering/context/scrutiny-method.md`. That document's "Lane binding" section
already fixes what a lane supplies: an item inventory, a layer vocabulary with discovery probes,
evidence sources mapped onto the §2 tiers, and protected-class defaults extending §7. Sections
1-12 are lane-independent and apply verbatim. The interview resolved every thread a design pass
would open: evidence tiering (Q7), verdict vocabulary (Q12), coupling (Q14, superseded by OD1 and
OD4), read-only posture (Q8), and the no-target fallback ladder (Q9).

## Type sketch (the only contract-level additions)

Both land in `plugins/overengineering/context/findings-artifact.md` under a `schema` bump from 1
to 2:

1. **`Layer` enum, five non-enforcement values appended:** `decision-records`, `documents`,
   `components`, `dependencies`, `source`. Enforcement kinds keep the existing ten values and route
   to `/overengineering:audit`.
2. **`Basis`, a new non-spine per-finding field**, always present, one of `measured` /
   `class-inferred` / `unexamined`. Non-spine by construction: the spine is closed and
   `overengineering:delta` diffs it, so the tag lives in the prose block and never changes a diff.

No new module, no runtime type, no cross-plugin contract. Consumers of the artifact are prose
skills only (`realign`, `delta`); no script parses it (verified: zero non-markdown hits for
`overengineering-findings`).

## Threads resolved upstream, not re-derived here

| Thread | Resolved by |
|---|---|
| Home and packaging | OD1: third lane inside `overengineering`, per ADR 0017 |
| Leaf name | OD2: `justify` |
| Method reuse | Intra-plugin pointer, ADR 0018 clause 1; no vendoring |
| Verdict ladder | Q12: §6 verbatim plus `Basis` |
| Findings artifact type | Inherits `type: overengineering-findings`, deliberately not `review-findings` |
