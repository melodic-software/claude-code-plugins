# Changelog for the recommendation-basis convention

Notable changes to the recommendation-basis contract (SemVer). Changing the grounding bar, the
label's values, or the re-emit shape is a major bump; additive guidance is a minor bump; docs-only
clarification is a patch.

## [1.0.2] - 2026-10-01

Patch, docs-only. The Boundary bullet on durable records of upstream-derived facts names the record
the upstream-drift convention now requires: our decision, a pointer, an as-of date and a recheck
trigger. No grounding bar, label value or re-emit shape changes.

## [1.0.1] - 2026-09-28

Adopters lists the skills that conform to 1.0.0 across `planning`, `source-control`, `github`,
`work-items`, `adhd`, `naming`, `architecture`, `code-tidying`, `debugging`, `claude-ops`,
`session-flow`, and `discipline`, and the byte-identical shipped copies of the contract those
plugins carry. No contract change.

## [1.0.0] - 2026-09-28

Initial contract: what counts as a recommendation, the local and external grounding bar, the
consequential threshold, the three outcomes (verified, judgment, withheld), and the old → new →
why re-statement. Adopted by the `discipline` plugin's loop Report step,
`/discipline:do-your-research`, and `/discipline:do-your-research-deep`.
