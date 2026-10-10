---
bump: patch
---

### Changed

- The observer analysis model (`observer_analysis_model`) now defaults to `claude-haiku-5-5`
  instead of `claude-haiku-4-5`, which Anthropic may retire as early as 2026-10-15
  ([model deprecations](https://platform.claude.com/docs/en/about-claude/model-deprecations)).
  Its description calls the default a small, fast model rather than the cheapest active tier.
