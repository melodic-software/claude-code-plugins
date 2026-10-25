---
abstract: Windows performance mode and CI queue measurement
evidence_use: internal
verification: pending
accepted: 2
---
# Research: Windows performance mode

Run status: complete

## Summary

Performance mode gives faster performance with less protection (M1).

## Sidecars

- perf: Performance mode gives faster performance with less protection (M1).

## Next-stage handoff

Settled:

- K9: builds cache dependencies by default.

Open:

- CI-02: the queue formula, see Gaps.

## Catalog

| ID | Measure |
|---|---|
| CI-02 | `started_at - created_at` |

## Fetch log

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| M1 | https://example.com/performance-mode | 1 | WebFetch | carries the claim |
