---
abstract: Which trust measures (revert rate, no-human-touch merge share, corrections converted to checks) claude-code-plugins can compute today from its own data.
evidence_use: publish
verification: fail rows 4,7,12 (research-verifier, 2026-11-12)
accepted: 7
---

# Trust measures computable in claude-code-plugins

Run status: complete

## Task restatement

For revert rate, the share of pull requests merged with no human touch, and corrections converted to
checks: name each measure's data source, whether it is computable now, the definition to use
(grounded in DORA and any published definition, and in what /work-items:measure-delivery,
/work-items:morning-brief and /corrections:codify already read or record), the value where a few
read-only commands compute it, and (owner addition) how the talk's slides 3 and 33-38 define or show
each measure. Feeds [issue #15668](https://github.com/melodic-software/claude-code-plugins/issues/15668).
Run settings: source breadth medium (Phases 0-2, Phase 3 and 4 skipped), research config
corroborators 2, recency 14/30/90 days, evidence use publish (all from the envelope).

## Summary

Decision left to the owner: whether to build a view, and for the no-human-touch share, which per-PR
signal would separate the owner's own actions from agent sessions under the same login.

- Revert rate: computable now from git through the existing skill. Value: C1, a revert-based proxy (see its qualifiers). Definitions: D1 (HIGH (single source)), D2 (HIGH (single source)), S1 (HIGH (single source)). Target resolution: C5 (MEDIUM). Talk: T1 (MEDIUM).
- No-human-touch share: lower bound computable now through gh. Value: C2 (MEDIUM). Definition: H1 (HIGH (single source)). Blocker: S2 (HIGH (single source)), C3 (MEDIUM). Talk: T2 (MEDIUM).
- Corrections converted to checks: not computable now. Evidence: S3 (HIGH (single source)), C4 (MEDIUM). Talk: T3 (MEDIUM).

## Sections

- findings: H1 (HIGH (single source)): "Jellyfish defines agentic-merged PRs as the fraction of merged pull requests whose only review activity came from AI tools, with no human review input before merge"
- computed: C1 (HIGH): "Over 2026-08-20 to 2026-11-11 on origin/main there were 7652 landings, of which 13 carry a revert subject, a revert rate of 0.17%"
- talk: T1 (MEDIUM): "The talk shows revert rate as the percent of commits reverted per month, and the speaker says the number of PRs that get reverted is steady at about half a percent"

| Section | File | Anchor |
|---|---|---|
| findings (definitions, skills, conflicts, gaps, fetch log) | RESEARCH-findings.md | #findings |
| computed (per-measure table, commands, values) | RESEARCH-computed.md | #computed |
| talk (slides read as data) | RESEARCH-talk.md | #the-talk-read-as-data |

## Next-stage handoff

Settled: D1 (HIGH (single source)), D2 (HIGH (single source)), H1 (HIGH (single source)), S1 (HIGH (single source)), S2 (HIGH (single source)), S3 (HIGH (single source)), C1.

Gaps: R1 (MEDIUM), R2 (MEDIUM), H2 (MEDIUM), C2 (MEDIUM), C3 (MEDIUM), C4 (MEDIUM), C5 (MEDIUM), T1 (MEDIUM), T2 (MEDIUM), T3 (MEDIUM).

Open: the per-PR signal for human versus agent action under the owner login; a tracked record linking a codify proposal to an installed check.

## Outcome gate

Run-owned rows graded off the artifact; rows 4, 7, 12 and 14 await the verifier; row 8 is the parent's.
