---
bump: minor
---

### Added

- A `medium` option (`auto` by default) sets where `/adhd:clarify` sends its decision table. Picking its value from a list in `/config` needs Claude Code v2.1.271 or later ([#12668](https://github.com/melodic-software/claude-code-plugins/issues/12668)).
- `prerequisites.json` declares `node`, which the medium resolver and the bundled prerequisites checker run on, so `/harness-ops:prerequisites` reports it when it is missing ([#12668](https://github.com/melodic-software/claude-code-plugins/issues/12668)).

### Changed

- `/adhd:clarify` resolves its medium through the shared resolver (`lib/view-settings.mjs resolve --lane adhd:clarify`) and prints its report line, `view: <medium> (<what decided it>)`, plus one line per notice, instead of reading the settings files itself ([#12668](https://github.com/melodic-software/claude-code-plugins/issues/12668)). The scopes are now the `--medium` argument, the plugin's `medium` option, the team file `docs/conventions/rendered-views.yaml` and its untracked personal override `docs/conventions/rendered-views.local.yaml`. `~/.claude/rendered-views.md`, `.claude/rendered-views.md` and `.claude/rendered-views.local.md` are retired: each gives a notice naming where to set its value. A `terminal` or `file` value in one of them still keeps the view local while no scope sets a value; a publishing value in them is ignored. A team file's publishing value used to force a local file. The resolver now ignores that value with a notice, and the skill's content rule picks where the table goes.
