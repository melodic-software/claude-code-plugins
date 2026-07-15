# Severity and confidence baseline

Shared vocabulary for every finding this plugin's agents and skills emit. **Consumer precedence:** when the consuming project defines its own severity vocabulary (a `REVIEW.md`, review guide, or project rule), read it and map findings to the project's tiers instead — this file is the fallback baseline, not an override.

## Severity tiers

| Tier | Definition | Action |
|---|---|---|
| **CRITICAL** | Must fix before merge: correctness bugs, security vulnerabilities, broken contracts, architecture violations that will cascade | Block until fixed |
| **IMPORTANT** | Should fix: convention drift, missing tests for new behavior, code duplication, error-handling gaps that degrade but do not break | Fix before or shortly after merge |
| **SUGGESTION** | Consider: naming improvements, minor refactoring opportunities, hardening with no current exploitability | Optional; author's judgment |

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
