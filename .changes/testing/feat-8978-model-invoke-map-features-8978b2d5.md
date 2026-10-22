---
bump: patch
---

### Changed

- **`/testing:map-features` can now be invoked by the model** ([#8978](https://github.com/melodic-software/claude-code-plugins/issues/8978)). Before, `disable-model-invocation: true` kept it user-typed only, and its description said "User-invoked only." It only writes a new map, never overwrites one and commits nothing, so the invocation-mode grade (#7974) flipped it to `false`. The description no longer carries the "User-invoked only." phrase.
