---
bump: patch
---

### Added

- Eval cases for scenarios T3 and T4 on the shared fixtures. `t3-setup-interactive-release` runs `/developer-experience:setup apply` on the bare `brackenfold` copy and checks that `AGENTS.md` keeps its lines and gains the pointer line, with judge graders on the conventions file it writes. `t4-check-old-location` runs `/developer-experience:setup check` on the legacy `tarnquill` copy with deterministic graders only: nothing written and the seeded files unchanged, the `.claude/` file reported as an old location, the false `--yes` line reported, and the missing `@AGENTS.md` import printed. ([#9993](https://github.com/melodic-software/claude-code-plugins/issues/9993))
