---
bump: patch
---

### Fixed

- An address-feedback round that finds every note of an earlier pr-verify FAIL already addressed stops `feedback-already-addressed` without the `needs-session` label. pr-verify judges that head on its own once its checks complete, and the lane's next run on the head clears the stop when a pass there lifts the `verify:earlier-fail` refusal, so no session builder is queued ([#18133](https://github.com/melodic-software/claude-code-plugins/pull/18133)).
