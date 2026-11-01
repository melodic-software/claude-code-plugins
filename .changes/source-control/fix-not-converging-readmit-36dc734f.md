---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py capped-close` takes `--reason feedback-not-converging`: it closes a lanes App pull request whose review rounds the pr-unblock lane stopped as not converging at the head, judged again from the lanes App's lane-stopped comment, and re-admits its issue for a fresh attempt, as it does at the verify cap ([#11023](https://github.com/melodic-software/claude-code-plugins/issues/11023)).
