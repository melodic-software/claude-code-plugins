---
topic: windows-performance
section: perf
abstract: Example Vendor's performance-mode page states the mode trades protection for speed (M1, HIGH (single source)).
claims:
  - claim: "Example Vendor's performance-mode page states the mode gives faster performance with less protection"
    id: M1
    confidence: HIGH (single source)
    single_source: "the page is the only publisher of its own text"
    tiers: [1]
    applies_to: version-independent
    sources:
      - url: "https://example.com/performance-mode"
        tier: 1
        pool: "example vendor docs"
        measures: "what the page states about performance mode"
        role: primary
        published: 2025-01-01
        applies_to: version-independent
        standing: current
    inference: "the claim restates the page"
    qualifiers: ["in most circumstances"]
  - claim: "Queue time is started_at minus created_at"
    id: CI-02
    confidence: MEDIUM
    tiers: [2]
    applies_to: version-independent
    sources: []
    inference: "one secondary source gives the formula"
    qualifiers: []
  - claim: "Builds cache dependencies by default"
    id: K9
    confidence: HIGH
    tiers: [1]
    applies_to: version-independent
    sources: []
    inference: "the build docs and two independent write-ups agree"
    qualifiers: []
produced_by: phase-2
---
# Performance mode

## Summary

See M1 (HIGH (single source)).

## Gaps

- CI-02 (MEDIUM): the queue formula has one secondary source.
