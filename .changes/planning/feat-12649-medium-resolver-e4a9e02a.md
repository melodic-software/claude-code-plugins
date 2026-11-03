---
bump: major
---

### Added

- a `medium` option for the planning views

  Set it to `terminal`, `file`, `artifact` or `hosted` (read as `artifact`) to
  choose where the plan, brainstorm, design, PRD and decision-table views go;
  `auto`, the default, keeps the shipped `file` default.

### Changed

- the planning views resolve the medium through the shared medium resolver

  The settings are a medium named in the request, the `medium` option, the
  team file `docs/conventions/rendered-views.yaml` and the personal override
  `docs/conventions/rendered-views.local.yaml`. A team file can keep a view
  local but never publishes one. The skill prints the report line naming the
  medium and what decided it.

### Removed

- `~/.claude/rendered-views.md`, `.claude/rendered-views.md` and
  `.claude/rendered-views.local.md` are no longer read

  Each gives one notice per project naming its value and where to set it
  instead.
