---
bump: patch
---

### Fixed

- `setup` check reads the Agent SDK state from a load-time row (`present`, `absent` or `unavailable`) instead of having the model probe the plugin data directory, which an eval run denies, and states the headless fallback's two caveats when the SDK is absent or unavailable; the four setup cases held out of the evals.json conversion are restored ([#13751](https://github.com/melodic-software/claude-code-plugins/issues/13751)).
