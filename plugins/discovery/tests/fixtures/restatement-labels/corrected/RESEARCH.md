---
abstract: Windows performance mode and CI queue measurement
evidence_use: internal
verification: pending
accepted: 2
---
# Research: Windows performance mode

Run status: complete

## Summary

See M1 (HIGH (single source)).

## Sidecars

- perf: Example Vendor's performance-mode page states the mode trades protection for speed (M1, HIGH (single source)).

## Next-stage handoff

Settled:

- K9.

Open:

- CI-02 (MEDIUM), see Gaps.

## Catalog

| ID | Measure |
|---|---|
| CI-02 | `started_at - created_at` (queue formula MEDIUM, see Gaps) |

## Fetch log

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| M1 | https://example.com/performance-mode | 1 | WebFetch | carries the claim |
