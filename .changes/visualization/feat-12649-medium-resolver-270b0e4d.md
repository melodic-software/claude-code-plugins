---
bump: major
---

### Changed

- `/visualization:present` and `/visualization:visualize` resolve the medium
  through the shared medium resolver

  The settings are the argument, this plugin's `medium` option, the team file
  `docs/conventions/rendered-views.yaml` and the personal override
  `docs/conventions/rendered-views.local.yaml`. A `terminal` or `file` value
  from any of them keeps the view local; `artifact` or `hosted` counts only
  from the argument, the option, or an untracked, gitignored personal
  override; a team file never publishes. Both skills print the report line
  naming the medium and what decided it. The deck gate's output carries that
  report in `report` in place of `warnings`.

### Removed

- `~/.claude/rendered-views.md`, `.claude/rendered-views.md` and
  `.claude/rendered-views.local.md` are no longer read

  Each gives one notice per project naming its value and where to set it
  instead: this plugin's `medium` option,
  `docs/conventions/rendered-views.yaml`, or
  `docs/conventions/rendered-views.local.yaml`.
