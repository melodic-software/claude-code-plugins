---
bump: patch
---

### Fixed

- A signed-out agy run (`authentication failed or timed out`) or a `RESOURCE_EXHAUSTED` quota error now opens the antigravity breaker, so later runs skip with one notice until `external-agents update antigravity` or the cool-down, instead of each waiting out agy's 60-second sign-in prompt.
