---
bump: minor
---

### Added

- A `medium` option: the per-user choice of where the `/discovery:blindspot` view goes (#12741).

### Changed

- `/discovery:blindspot` resolves the view's medium through the shared resolver (`lib/view-settings.mjs resolve --lane discovery:blindspot`) and prints its report line, in place of reading the `rendered-views` files itself (#12741). `~/.claude/rendered-views.md` and `.claude/rendered-views*.md` now give a retirement notice and never a publishing value; set the medium in the `medium` option or `docs/conventions/rendered-views.yaml` and its `.local.yaml` override instead.
