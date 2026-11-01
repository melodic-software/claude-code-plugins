---
tags: ['be-concise']
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Condenses each section while the destination''s structural contract survives intact, because a PR body''s gate is part of the completeness floor. The opening line `Closes #123` is still the first line. All four required headings remain, each with non-empty content: `## Summary`, `## Fix`, `## Verification`, `## Related`. Specific values survive: the `pricing.tier.imported` event, the `PRICE_CACHE_TTL_SECONDS` change from 3600 to 900, the `pytest tests/pricing/test_cache.py` command, and the issue references #118 and #131. Summary opens with the effect on customers rather than the July import-job history. Before and after word counts are reported.'
---

Tighten this pull request body before I open the PR: pr-body-pricing-cache.md. Reviewers are not going to read four paragraphs.
