---
bump: major
---

### Added

- A `medium` option for the `/work-items:triage` board page ([#12711](https://github.com/melodic-software/claude-code-plugins/issues/12711)). Unset or `auto`, the page goes to a local file as before. Its fixed list of values is the plugin's first `options` field, so this plugin now needs Claude Code v2.1.271 or later.

### Changed

- `/work-items:triage` resolves its board page's medium through the shared medium resolver (`lib/view-settings.mjs`, lane `work-items:triage`) and prints the report line naming the medium and what decided it ([#12711](https://github.com/melodic-software/claude-code-plugins/issues/12711)). The settings are this plugin's `medium` option, the team file `docs/conventions/rendered-views.yaml` and the personal override `docs/conventions/rendered-views.local.yaml`; a team file never publishes.

### Removed

- `/work-items:triage` no longer reads `~/.claude/rendered-views.md`, `.claude/rendered-views.md` or `.claude/rendered-views.local.md` ([#12711](https://github.com/melodic-software/claude-code-plugins/issues/12711)). Each gives a notice naming its value and where to set it instead.
