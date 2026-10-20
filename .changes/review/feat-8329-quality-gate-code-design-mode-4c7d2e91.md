---
bump: minor
---

### Added

- `/review:quality-gate code-design` reviews a change for design that makes the next change costly. It loads the consumer's review criteria through the standards resolution ladder and falls back to small bundled criteria (Duplicated Code, Shotgun Surgery, Speculative Generality), run by a fresh-context `review:brief-reviewer`. Repetition is CRITICAL only when the diff introduces a copy in code that no shared source or sync check keeps aligned, and the finding names the repeated fact and the later change that would make the copies diverge; Markdown repetition, change cascades and the `prototype` quality bar stay SUGGESTION. A consumer standard that contradicts a bundled default wins, and the report says `Overrides bundled default <principle> per <standards file>`; with no quality bar given, the review rates as production and says so. The mode takes the phase-boundary inputs like every other.
