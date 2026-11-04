---
bump: minor
---

### Changed

- **`/codebase-health:audit` resolves its view medium through the shared resolver.** The rendered-view offer now runs `lib/view-settings.mjs resolve --lane codebase-health:audit` and prints the resolver's report line and notices. The skill no longer reads `~/.claude/rendered-views.md`, `.claude/rendered-views.md` or `.claude/rendered-views.local.md` itself: the resolver gives a notice for each one naming its new home, a `terminal` or `file` value there still keeps the view local when no other setting decides, and a publishing value there is ignored. The `rendered-views` settings under `docs/conventions/` and the new `medium` plugin option decide ([#12677](https://github.com/melodic-software/claude-code-plugins/issues/12677)).

### Added

- **`medium` option.** A per-user default for the audit's rendered-view offer (default `auto`), passed to the shared medium resolver; the retired `~/.claude/rendered-views.md` notice points at it. Its fixed list of values needs Claude Code v2.1.271 or later.
