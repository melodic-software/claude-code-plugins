# Attribution: restated upstream facts detector

Recorded park for
[#3525](https://github.com/melodic-software/claude-code-plugins/issues/3525).
`/attribution:audit` (formerly `/provenance:audit`) detects verbatim copies
that reach `fingerprint-confirmed`. Restated upstream facts with no 15-word
span never become actionable. The copy and fingerprint lane stays as written.

## Decision

**Park the design gap. Keep the copy/fingerprint lane verbatim.** Do not add
a `restated-upstream-fact` class, a second judgment rubric, or a relay row
for paraphrase candidates.

- **Option A (taken):** park. Nomination may still describe restated
  constants; the pipeline keeps routing `paraphrase` / `summary` to
  report-only. Fix eligibility stays lexical (`fingerprint-confirmed` only).
- **Option B (declined):** add the second rubric and relay row (or the
  broader redesign) from this record.

**Claim:** restated upstream facts are a known design gap, not a detector
bug. The copy lane stays. A paraphrase can never be `fingerprint-confirmed`.
**Basis:** #3525 (repo-wide run nominated 17 of 18 #3524 prose surfaces, then
dropped them as `paraphrase-candidate` / `below-rule` / `not-found`).
`plugins/attribution/skills/audit/reference/rubric.md` "Tier mapping":
"A paraphrase can never be `fingerprint-confirmed`".
`plugins/attribution/skills/audit/reference/nomination.md` "What the panel
never decides": a unanimous STANDS on a paraphrase is still `llm-suspected`.
`plugins/attribution/skills/audit/SKILL.md` maps tier by evidence, never
from confidence. `evals/fixtures/restated-no-pointer.md` already seeds the
shape; it is not a live detector class.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds the second-rubric / relay-row (or the
redesign) and unparks #3525. Do not reopen the no-CI-gate decision owned by
the upstream-drift convention.

## Rationale

- The nominator already hunts facts. The failure is downstream routing, not
  recall. Changing routing is a judgment-pipeline contract change (C4).
- Keep existing copy-lane sentences byte-identical. This record does not
  rewrite rubric, nomination, or dispositions text.
- No CI gate: upstream-drift's 2026-08-12 decision (upheld 2026-08-31)
  stands.

## Revisit when

- a maintainer funds the second rubric plus a relay row for
  non-lexical candidates, with a named adversary and an eval corpus that
  includes distilling-file negatives, or
- the upstream-drift convention's reopen condition for a detector-without-
  suppression-list is met (that record's business, not this issue's).

## Prior requests

- #3525 (2026-09-28): needs-human; Option A recorded here.
- #3524: frontmatter-alignment census that demonstrated the gap.
