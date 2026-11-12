---
abstract: Which techniques on Sridharan's test-stage chart apply to plugin-marketplace consumers, which this marketplace covers, and whether a coverage lens is worth adding
evidence_use: publish
verification: fail rows 12 (research-verifier, 2026-11-12)
accepted: 6
---

# Test-stage chart techniques against claude-code-plugins

Run status: complete

## Task restatement

For the 42 entries on the test-stage chart shown as slide 31 of Lauren Tan's talk "All Code Is
Slop (Except Mine)" (AI Engineer Code Summit, 2026-11-11): name the chart's primary source, decide
per technique whether it applies to what consumers of a Claude Code plugin marketplace build, name
the skill in this repository's `plugins/` that covers it (or the gap), and answer yes or no on
adding a technique-coverage lens to `/testing:plan` or the verification plugin. Feeds
[issue 15667](https://github.com/melodic-software/claude-code-plugins/issues/15667).

Evidence use: publish. Source breadth: medium (Phases 0 to 2; 3 and 4 skipped). Research config:
corroborators=2, recency 14/30/90, from the envelope.

## Summary

Primary source: Cindy Sridharan's 2018 Medium post, which redraws as three phases a two-column
chart from her December 2017 post (O1, HIGH (single source)); the slide adds three entries to the
2018 chart (O2, HIGH (single source)). Her scope limit (O3, HIGH (single source)) covers the
production phases and not the pre-production column: it accounts for 15 of the 16 ops-only rows,
and the sixteenth, penetration tests, is ops by judgment. Re-derived coverage is 25 of 42 at least
partly, with two rows moved from the earlier table (coverage sidecar). Quoted passages of the 2018
post are saved in RESEARCH-snapshot.md. Lens recommendation: no to a full
technique-coverage lens; a narrow two-row addition to `/testing:plan` for fuzz and contract tests
is the alternative (lens sidecar; judgment resting on R1, HIGH (single source), and the evidence
for its current practice is MEDIUM: P1, P2).

## Sidecar abstracts

- origin: O1 (HIGH (single source)): "Cindy Sridharan published the three-phase test-stage chart in her Medium post Testing in Production, the safe way, dated Mar 25, 2018, after a two-column chart in her December 2017 post Testing Microservices, the sane way"
- snapshot: Verbatim passages of the 2018 post the origin claims quote, saved with the fetch command and date so a verifier can grade them when Medium refuses a fetch
- coverage: R1 (HIGH (single source)): "/testing:plan maps changed files to unit, integration, architecture, E2E, analyzer, property and characterization or differential tests, and names no fuzz, contract, load, chaos or production-stage technique"
- lens: P1 (MEDIUM): "Pact documentation defines contract testing as checking each application in isolation against a shared contract and implements it consumer-driven, with a broker and can-i-deploy for CI"
- process: Phase analyses, fetch log, conflicts, gaps, recency status and the run-owned outcome-gate result

## Sections

| Section | File | Anchor |
|---|---|---|
| origin | RESEARCH-origin.md | #origin |
| snapshot | RESEARCH-snapshot.md | #snapshot-of-the-2018-post |
| coverage | RESEARCH-coverage.md | #coverage |
| lens | RESEARCH-lens.md | #lens |
| process | RESEARCH-process.md | #process |

## Next-stage handoff

- Settled: O1 (HIGH (single source)), O2 (HIGH (single source)), O3 (HIGH (single source)),
  R1 (HIGH (single source)), R2 (HIGH (single source)), R3 (HIGH (single source)).
- Gaps: P1 (MEDIUM), P2 (MEDIUM); who added the three entries the slide adds; current practice for
  rows other than contract and fuzz (judgment in the table).
- Open decision for the owner: whether to take the narrow two-row `/testing:plan` addition
  (lens sidecar). The per-technique applicability verdicts and the lens recommendation are
  judgment.
- Project fit: parent-owned.

## Outcome gate

Run-owned rows pass (process sidecar). Ledger and source-applicability verdicts are the scripts'
exit statuses, reported in the hand-back. Verifier rows 4, 7, 12, 14 pending; project fit (8) is
the parent's.
