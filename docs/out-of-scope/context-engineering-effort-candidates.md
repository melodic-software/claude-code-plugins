# Context-engineering effort: three deferred candidates

## Decision

**Deferred: record positions; no unpaid vertical.** This repository does not open a parallel
context-engineering implementation lane for the three candidate inputs in
[#3593](https://github.com/melodic-software/claude-code-plugins/issues/3593). Each stays a
position for its incumbent owner. ADR 0004 D-3 (no bulk `plugins/**` sweep; findings land in the
plugin that already owns the surface) still binds.

**Claim:** the three candidates are planning inputs, not a funded vertical; absorbing or
declining each belongs to the incumbent effort's check-design work, not to an autonomous
implementation pass. **Basis:** #3593 body (reroute from PR #3592 / ADR 0025 onto ADR 0004);
ADR 0004 D-1 and D-3; triage 2026-09-06 (human-gated absorption decision). **As of:**
2026-09-28. **Recheck:** a maintainer of the incumbent effort absorbs or declines each candidate
in a named, funded check-design pass, or unparks #3593.

## Positions

| Candidate | Owner | Position |
|---|---|---|
| skill-quality genericness check ("could this skill body be pasted into any repo unchanged?") | `skill-quality:check` | Defer. Resolution belongs to that plugin's check-design work. No new check ships from this issue. |
| audit-instructions I29 widening (companion-article repetition-myth duplication lens on I29-a / I29-b) | `claude-config:audit-instructions` | Defer. Shipped families stay I29-a description-restatement and I29-b sibling-recoverable. No unpaid scanner widening. |
| claude-memory `/doctor` cross-ref (prerequisite contract: absence classification and coverage disclosure) | `claude-memory` | Defer. No cross-ref ships from this issue. |

**Re-inventory note (standing):** any sweep that recorded instruction-surface counts before
2026-09-01 is stale relative to the unknowns waves in PR #3592. Treat those counts as leads, not
facts. **Claim:** pre-2026-09-01 surface counts are not current inventory. **Basis:** #3593
re-inventory note; PR #3592 contract lines across eight plugins. **As of:** 2026-09-28.
**Recheck:** a new inventory pass records current counts under a dated stamp.

## Rationale

- Briefing the candidates as independent work would recreate the parallel lane ADR 0025 closed.
- None of the three is a missing measurement with a designed probe; each is a product decision
  about whether to extend a shipped check. That is not drain-shipper work.

## Revisit when

- The incumbent effort schedules check-design for one of the three owners, or
- A maintainer unparks #3593 with an explicit absorb/decline per candidate.

## Prior requests

- #3593 (2026-09-28): three candidate inputs plus re-inventory note from the unknowns
  integration; drain shipper records positions and parks (no vertical executed).
