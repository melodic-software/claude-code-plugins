# Changelog for the recommendation-basis convention

Notable changes to the recommendation-basis contract (SemVer). Changing the grounding bar, the
label's values, or the re-emit shape is a major bump; additive guidance is a minor bump; docs-only
clarification is a patch.

## [2.0.0] - 2026-10-04

Major: the grounding bar's external side changes. It no longer asks for "current consensus", which
a popular but wrong pattern passes. For a tool, version, or API, official documentation still comes
first; for a design pattern, the authority is the canonical source that defines it and the
recognized experts who build on it, and recency never discounts a canonical definition. A new
"Popularity is not correctness" bullet requires checking a pattern found in a template, sample, or
popular repository against the principle it claims to serve, and keeps recall honest: a book cited
from memory is recall, while a canonical catalog page fetched this session verifies the pattern's
definition. The plugin-shipped copies carry the change, and the planning interview and the
architecture Design-It-Twice step, which restated the old wording, now state the new one. The
label's values and the re-emit shape are unchanged.

## [1.1.0] - 2026-10-02

Minor, additive. The Basis label section adds the `single source` qualifier: a recommendation
resting on a first-party content claim that `/discovery:research` accepted with a `single source`
flag stays `verified` and may ground a code edit, and its label and the record beside the edit
carry the flag, `Basis: verified (single source), <url>`. The label's two values, the grounding bar
and the re-emit shape are unchanged, so earlier adopters still conform. The plugin-shipped copies
leave the qualifier out because it applies only to research output.

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
