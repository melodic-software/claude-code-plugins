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

## Security severity mapping

The `security-reviewer` agent emits P1–P5 (CVSS-anchored). Fold into tiers as: P1/P2 → CRITICAL, P3 → IMPORTANT, P4/P5 → SUGGESTION.

**This fold decides the tier for a P-scored finding and takes precedence over the tier tests above.** The P-level already encodes exploitability and impact, so a P3 folds to IMPORTANT rather than being re-tested against CRITICAL's "unsafe result" clause and promoted.
