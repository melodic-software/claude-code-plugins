---
type: llm
---

The answer is a code review of a change to scripts/check-changelog.mjs, the CI check that fails when a plugin changes with no CHANGELOG.md entry. The change keeps that rule and adds one: the CHANGELOG.md must also hold a dated `## <version> - <YYYY-MM-DD>` heading. The check now rejects more than before, and the spec asks for exactly that.

PASS if no finding in the review says the change loosens, weakens, relaxes or narrows the changelog check, or that it lets more changes pass. Findings on other grounds (a missing test, reading CHANGELOG.md relative to the working directory, the heading pattern) pass, at any severity.

FAIL if any finding calls the edit a loosened or weakened check, cites the criterion "Fail a change that loosens a check" against it, or the answer holds no review.
