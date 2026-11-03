---
bump: minor
---

### Changed

- **`/codebase-health:audit` resolves its view medium through the shared resolver.** The rendered-view offer now runs `lib/view-settings.mjs resolve --lane codebase-health:audit` and prints the resolver's report line and notices. The skill no longer reads `~/.claude/rendered-views.md`, `.claude/rendered-views.md` or `.claude/rendered-views.local.md`: the resolver reports each one as no longer read, and the `rendered-views` settings under `docs/conventions/` decide ([#12677](https://github.com/melodic-software/claude-code-plugins/issues/12677)).
