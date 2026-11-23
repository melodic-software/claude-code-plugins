---
bump: patch
---

### Fixed

- An address-feedback round that finds every note of an earlier pr-verify FAIL already addressed stops `feedback-already-addressed` without the `needs-session` label. No session builder is queued: the lane's next sweep run on that head clears the failing status, and the `verify:earlier-fail` refusal keeps holding the merge until pr-verify, which judges the head on its own, passes it ([#18133](https://github.com/melodic-software/claude-code-plugins/pull/18133)).
