---
bump: patch
---

### Changed

- `/review:explain-change` names where a digest page goes from the shared medium registry instead of its own list of medium values ([#12670](https://github.com/melodic-software/claude-code-plugins/issues/12670)): `digest-policy.mjs` now prints `medium.where` and `medium.publishes`, and the skill reads them.
