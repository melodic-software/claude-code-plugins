---
bump: patch
---

### Fixed

- The babysit merge gate reruns a review that failed on GitHub's API rate limit (`publish-rate-limit`) one hour after its job finished, matching the installation pool's hourly reset, instead of five. A `rate-limit` failure keeps the five-hour plan-window wait, and a check with both classes waits the longer ([#18037](https://github.com/melodic-software/claude-code-plugins/issues/18037)).
