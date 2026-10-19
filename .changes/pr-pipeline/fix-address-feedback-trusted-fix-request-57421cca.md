---
bump: minor
---

### Changed

- `address-feedback` now also works a review thread the lanes App never commented on when a
  trusted person with write or admin permission replies to the reviewer bot's finding with a fix
  request (`PR-fix lane: please fix this finding`); every other comment must still be the reviewer
  bot's or a trusted person's. The select step, the reply job's re-read and
  `pr-feedback-dispatch.yml` judge threads the same way
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
  The dispatcher still starts only when a review run completes. `version` stays 2.
