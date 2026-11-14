---
bump: patch
---

### Fixed

- **codify's finding classes name the current rung id `syntax-pattern-rule`.** The class table, the security dimension row, the counting-rung list and the next-step entry no longer write the old `semgrep-rule` id, and the .NET-only note names the rung by id. The pointer to the rule-writing plugin and Semgrep's documentation is unchanged.
- **codify's report notes an old rung id read through the ladder's alias.** When a consumer's instructions or a stub still use an old rung id, the report gets one line naming the old id and the current one, as the enforcement ladder's alias requires.
