---
bump: patch
---

### Changed

- `/work-items:work` offers the `report-delivered` stop for any issue whose report is the whole result and needs no commit, not only a `work-class: read-only` one (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)). The capability-tier reference and triage's outcome context now say security-surface work routes to the frontier tier per the convention's tier rules, not by work class.
