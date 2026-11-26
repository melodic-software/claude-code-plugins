---
bump: minor
---

### Added

- behavior-probes: a case's `turns` (user messages such as `/clear`) run before its prompt over stream-json input, and outcome `reply` judges the run's last reply against `reply_match`, where `<session8>` stands for the answering session's id prefix.
- behavior-probes: `session-start` cases check that a SessionStart hook's context reaches the model on startup, after `/clear` and after `/compact`.

### Changed

- behavior-probes: a run whose stream reports a rejected rate limit (the usage limit) is inconclusive and skips every case after it; an `allowed` rate-limit event is ignored.
