---
bump: patch
---

### Changed

- **`/ai-briefing:generate` resolves the view medium through the shared resolver** ([#12722](https://github.com/melodic-software/claude-code-plugins/issues/12722)). It runs `lib/view-settings.mjs resolve --lane ai-briefing:generate` and prints the report line and any notice; it no longer names the retired `~/.claude/rendered-views.md` or `.claude/rendered-views.md` layers. Only `--format` still selects HTML or PPTX.
