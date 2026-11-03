---
bump: patch
---

### Fixed

- `be-concise` declines again to restructure a dense message without shortening it and to reshape agent-facing instruction prose, even when the plugin it routes to is not enabled ([#12846](https://github.com/melodic-software/claude-code-plugins/issues/12846)).
- `be-concise` runs its semantic-diff check when the original has more than three paragraphs or more than 250 words. It used to say "longer than a few paragraphs", which a model could not check.
- Routes to `docs-hygiene` skills say "enabled" where they said "installed".
- The wall-of-text eval fixture uses a relative deadline in place of a date that has passed.
