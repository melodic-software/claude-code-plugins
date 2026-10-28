---
bump: patch
---

### Changed

- `/work-items:work` opens a `stopped` reason with a code the issue lane routes by: `host-only`, `intent-change`, `design-change`, `security-risk` or `cost-risk`. A reason with none still goes to a person. Runs on [#6930](https://github.com/melodic-software/claude-code-plugins/issues/6930) and [#6887](https://github.com/melodic-software/claude-code-plugins/issues/6887) stopped for a host-only need in free text, so each went to `needs-human` instead of the host queue.
