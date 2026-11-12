---
topic: test-stage-chart
section: lens
abstract: 'P1 (MEDIUM): "Pact documentation defines contract testing as checking each application in isolation against a shared contract and implements it consumer-driven, with a broker and can-i-deploy for CI"'
claims:
  - claim: "Pact documentation defines contract testing as checking each application in isolation against a shared contract and implements it consumer-driven, with a broker and can-i-deploy for CI"
    id: P1
    confidence: MEDIUM
    claim_kind: content
    source_owner: "Pact Foundation"
    tiers: [1]
    applies_to: "version-independent"
    sources:
      - url: "https://docs.pact.io/"
        tier: 1
        pool: "Pact Foundation"
        measures: "the docs introduction (last updated Aug 25, 2026) and the consumer guide, read as search excerpts, not fetched directly"
        role: primary
        published: 2026-08-25
        dated_by: printed
        applies_to: "version-independent"
        standing: current
    inference: "The excerpts state the definition and the consumer-driven, broker and can-i-deploy workflow; MEDIUM because the page was not fetched directly and no independent corroborator was read."
    qualifiers:
      - "Pact also names provider contract testing against an OpenAPI document as a weaker variant."
  - claim: "Go ships coverage-guided native fuzzing in its standard toolchain from Go 1.18, and OSS-Fuzz runs native Go fuzz tests"
    id: P2
    confidence: MEDIUM
    claim_kind: content
    source_owner: "Go project (Google)"
    tiers: [1]
    applies_to: "Go 1.18+"
    sources:
      - url: "https://go.dev/doc/security/fuzz/"
        tier: 1
        pool: "Go project (Google)"
        measures: "the Go Fuzzing page read as a search excerpt: native fuzzing in the standard toolchain beginning in Go 1.18, coverage guidance, supported by OSS-Fuzz; the page prints no date"
        role: primary
        published: undated
        applies_to: "Go 1.18+"
        standing: historical
      - url: "https://google.github.io/oss-fuzz/getting-started/new-project-guide/go-lang/"
        tier: 1
        pool: "Google OSS-Fuzz"
        measures: "OSS-Fuzz Go guide read as a search excerpt: supports fuzzers written for the native Go 1.18 engine; undated"
        role: corroborator
        published: undated
        applies_to: "Go 1.18+"
        standing: historical
    inference: "Both excerpts state the claim; MEDIUM because neither page was fetched directly, neither is dated, and the Go release notes were not checked."
    qualifiers:
      - "Go only; other ecosystems a consumer uses (.NET, TypeScript, Python) have their own fuzzers, not researched this run."
produced_by: phase-2
---

# Lens

## Decision: add a technique-coverage lens?

**Recommendation: no** to a 42-row technique-coverage lens in `/testing:plan` or the verification
plugin. Basis: judgment, resting on the coverage and origin sidecars:

1. 16 of the 42 rows need a running production service or target: 15 sit in the deploy, release
   and post-release phases, which the 2018 post scopes to services the engineers deploy themselves
   (origin sidecar, scope section), and penetration tests is marked ops by judgment. A plugin skill
   run inside a consumer repository can only list those as absent, which is a report with no
   per-change action.
2. `/testing:plan` is change-driven: it maps each changed file to the test types it needs (coverage
   sidecar, first evidence entry). A repository-wide "which of the 42 do you have" inventory answers a
   different question, and nobody named acts on it per change.
3. The repo-applicable gaps are few and specific (coverage sidecar, Counts). They fit as rows in
   the existing classification table, not as a new lens.

**Narrow alternative, if the owner wants the gaps closed:** two rows in `/testing:plan`'s
classification table, each routed to `/testing:write`:

- Parser, decoder or handler of untrusted input: a fuzz target beside the property tests, using
  the ecosystem's native or standard fuzzer (Go example in the Gaps below).
- Client of, or endpoint consumed by, another service: a consumer-driven contract test (Pact
  example in the Gaps below).

Formal verification stays with its parked owner decision; threat modeling and live tap compare stay
outside a test plan.

## Current-practice evidence (Gaps, MEDIUM)

P1 (MEDIUM): "Pact documentation defines contract testing as checking each application in isolation against a shared contract and implements it consumer-driven, with a broker and can-i-deploy for CI"

P2 (MEDIUM): "Go ships coverage-guided native fuzzing in its standard toolchain from Go 1.18, and OSS-Fuzz runs native Go fuzz tests"

Both stay Gaps: the pages were read as search excerpts, not fetched directly, and neither has a
second independent corroborator. They inform the narrow alternative; neither is accepted.
