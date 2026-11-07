---
bump: patch
---

### Fixed

- `/work-items:setup apply` run unattended with no binding and no usable `gh` now names its blocker, "tracker binding needs a provider decision", in SKILL.md, so the run reports it without first reading `reference/autonomous-apply.md` ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
