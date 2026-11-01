---
bump: patch
---

### Fixed

- `feedback-not-converging` no longer leaves a lanes App pull request open on a failing status. When the lanes App's address-feedback lane-stopped comment names that reason at the current head, the pr-merge lane closes the pull request and re-admits its issue for a fresh attempt, as the verify cap does (`capped-close --reason feedback-not-converging`). The reason is read from that comment, never from a status description ([#11023](https://github.com/melodic-software/claude-code-plugins/issues/11023)).
- The lane-stopped comment for `feedback-not-converging` on a lanes App pull request now says pr-merge closes it, and that adding `do-not-merge` first keeps it open ([#11023](https://github.com/melodic-software/claude-code-plugins/issues/11023)).
