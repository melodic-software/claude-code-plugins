---
bump: minor
---

### Added

- `lib/prior-findings.mjs` lists a CI review lane's own earlier findings on a pull request for its wrapper to hand the model: inline review threads, reviews and PR comments, kept only when the github-actions bot wrote them (by numeric id), no other account edited them, and they carry the lane's `claude-lane:` footer or reviewed-head marker. For each anchored finding on a thread still open it records whether `git diff <posted head> HEAD` touches the lines it names (a resolved thread always answers yes), and it counts the lane's rounds against `loop.review-rounds` read from a default-branch `pr-pipeline.yaml` ([#7777](https://github.com/melodic-software/claude-code-plugins/issues/7777)).

### Changed

- `/review:code-review` and `/review:security-review` read a `PRIOR FINDINGS:` file when the wrapper names one: a finding the lane already posted on an open thread whose lines are unchanged since is not posted again, at any severity, and gets one uncounted `already posted` summary line, since that open thread still holds the merge. Past the round cap the code lane posts only blocking findings and the security lane only CRITICAL and IMPORTANT ones. With no such file both lanes review as before ([#7777](https://github.com/melodic-software/claude-code-plugins/issues/7777)).
