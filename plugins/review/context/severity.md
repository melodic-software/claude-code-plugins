# Severity and confidence baseline

Shared vocabulary for every finding this plugin's agents and skills emit. **Consumer precedence:** when the consuming project defines its own severity vocabulary (a `REVIEW.md`, review guide, or project rule), read it and map findings to the project's tiers instead — this file is the fallback baseline, not an override.

## Severity tiers

Apply the tests in order; the first tier whose test the finding satisfies is its tier. **The test decides the tier — the examples illustrate the test rather than enumerating the tier.** Argue a finding's tier from its test; resemblance to a listed example is not that argument.

| Tier | Test | Illustrative findings | Action |
|---|---|---|---|
| **CRITICAL** | You can name a concrete input, caller, or subsequent **otherwise-correct** change that the defect makes produce a wrong result, an unsafe one, or none at all | correctness bugs, security vulnerabilities, broken contracts, architecture violations that will cascade | Block until fixed |
| **IMPORTANT** | Nothing produces a wrong result today, but the finding names a stated rule the change violates, behavior it adds that no test covers, or a degradation or maintenance cost with a named trigger | convention drift, missing tests for new behavior, code duplication, error-handling gaps that degrade but do not break | Fix before or shortly after merge |
| **SUGGESTION** | Neither test holds — the finding is a preference among alternatives that all work, or hardening with no path reachable today | naming improvements, minor refactoring opportunities, hardening with no current exploitability | Optional; author's judgment |

Stating the bar as a decidable test rather than a qualitative label follows the Sonnet 5 prompting guide, "Code review harnesses" — "be concrete about where the bar is rather than using qualitative terms like `important`" (<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5>). The tests restate the existing bars rather than moving any finding between tiers.

## Confidence axis

Independent of severity — how sure the reviewer is that the finding is real:

| Value | Meaning |
|---|---|
| `high` | Verified at the call site (data flow traced, file read, behavior confirmed) |
| `medium` | Pattern match with partial verification |
| `low` | Suspicious pattern, unverified |
| `unscored` | The emitting surface reported no confidence — absence of a score is NOT low confidence |

**Rank order: `high` > `medium` > `unscored` > `low`.** Ranking reads the axis in that order, which
puts `low` BELOW an absent score: a surface that emits `low` to express uncertainty ranks its
finding under one nobody reported. Emit `high` or omit the field. This file owns the order; every
consumer that ranks on confidence reads it here rather than restating it.

## Vocabulary

**In this plugin, "axis" means one of the two above — severity or confidence.** They are the two
independent scales every finding carries, and merging and ranking findings across them is what
`fanout`'s normalization pipeline exists to do; a rule forbidding that would negate the pipeline.

A *review perspective* — standards conformance vs spec conformance, code vs architecture vs
security — is a **lens**, not an axis. Lenses are not comparable to each other and are presented
separately (`quality-gate` runs one per invocation; `fanout` regroups its merged queue by dimension
alongside the ranked view). Three incompatible senses of "axis" were live across this plugin's docs
before this note; use "lens" for perspectives and keep "axis" for severity and confidence.

## Security severity mapping

The `security-reviewer` agent emits P1–P5 (CVSS-anchored). Fold into tiers as: P1/P2 → CRITICAL, P3 → IMPORTANT, P4/P5 → SUGGESTION.

**This fold decides the tier for a P-scored finding and takes precedence over the tier tests above.** The P-level already encodes exploitability and impact, so a P3 folds to IMPORTANT rather than being re-tested against CRITICAL's "unsafe result" clause and promoted.
