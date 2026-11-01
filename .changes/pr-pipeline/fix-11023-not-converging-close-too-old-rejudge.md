---
bump: patch
---

### Fixed

- `feedback-not-converging` no longer leaves a lanes App pull request open on a failing status. When the lanes App's address-feedback lane-stopped comment names that reason at the current head, the pr-merge lane closes the pull request and re-admits its issue for a fresh attempt, as the verify cap does (`capped-close --reason feedback-not-converging`). The reason is read from that comment, never from a status description ([#11023](https://github.com/melodic-software/claude-code-plugins/issues/11023)).
- `verify:too-old`: resolve-pr judges a head again, with reason `too-old`, when the pull request is past `TOO_OLD_DAYS` and no pass there came from a pr-verify run created since. The lost-run reconciler re-runs that head's passed checks to start the judgment. The capped close of a too-old pull request now waits a day for it ([#11023](https://github.com/melodic-software/claude-code-plugins/issues/11023)).
