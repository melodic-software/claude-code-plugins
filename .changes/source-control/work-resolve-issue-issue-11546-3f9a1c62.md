---
bump: patch
---

### Fixed

- `/source-control:babysit-loop` passes `--unattended` to each `/source-control:babysit-prs` call it makes, so a merge-lane cycle records the `/autofix-pr` offer instead of reaching an ask nobody answers. The looped `worker` and `autopilot` lines in `/source-control:babysit-prs` and its autopilot reference pass `--unattended` too ([#11546](https://github.com/melodic-software/claude-code-plugins/issues/11546)).
