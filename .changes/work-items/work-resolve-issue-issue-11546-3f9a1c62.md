---
bump: patch
---

### Fixed

- `/work-items:work` passes `--unattended` to each skill it calls that takes it when it runs unattended: in an autonomous invocation it passes it to `/debugging:debug`, `/implementation:implement-dispatch`, `/source-control:pull-request create --pushed` and `/source-control:babysit-prs`, and in CI mode it passes it to `/debugging:debug` and `/discovery:research`. Before, such a run could reach an ask nobody answers ([#11546](https://github.com/melodic-software/claude-code-plugins/issues/11546)).
