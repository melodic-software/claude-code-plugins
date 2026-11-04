---
bump: major
---

### Added

- A `medium` plugin option (default `auto`) sets where `/education:illustrate`'s page and `/education:teach`'s topic lessons go.

### Changed

- `/education:illustrate` and `/education:teach` resolve where their views go through the shared medium resolver (`lib/view-settings.mjs`, lanes `education:illustrate` and `education:teach`) and print the resolver's report line naming the medium and what decided it ([#12682](https://github.com/melodic-software/claude-code-plugins/issues/12682)).

  The settings are a medium named in the request, the plugin's `medium` option, the team file `docs/conventions/rendered-views.yaml` and the personal override `docs/conventions/rendered-views.local.yaml`. A team file can keep a view local but never publishes it.

### Removed

- `/education:illustrate` and `/education:teach` no longer publish on an `artifact` or `hosted` value from `~/.claude/rendered-views.md`, `.claude/rendered-views.md`, `.claude/rendered-views.local.md` or a fenced config block in `docs/conventions/rendered-views.md`

  These sources are retired. A `terminal` or `file` value in one still keeps the view local when the request names no medium and no other setting keeps it local. Each file gives one notice naming its value and where to set it instead.
