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
  A fix request posted after the head's review starts the round when an account on the trusted-actor list runs
  `gh workflow run pr-unblock.yml -R melodic-software/claude-code-plugins -f pr-number=<n> -f activity=address-feedback`.
  `version` stays 2.
