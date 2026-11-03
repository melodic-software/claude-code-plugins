---
bump: major
---

### Added

- a `medium` option for `/review:explain-change`

  Set it to `terminal`, `file`, `artifact` or `hosted` to choose where a digest
  page goes; `auto`, the default, leaves the choice to the shipped `artifact`
  default and the publish gate. The skill passes it to the policy script as
  `--option`.

### Changed

- the digest resolves its medium through the shared medium resolver

  The team file is now `docs/conventions/rendered-views.yaml`, read from the
  pull request's base commit, and the personal override is
  `docs/conventions/rendered-views.local.yaml`. A `terminal` or `file` value
  from any of them keeps the page local; `artifact` or `hosted` counts only
  from the `medium` option or an untracked, gitignored personal override. The
  policy output's `medium` gains `explicit`, which says when to pass
  `--explicit` to the publish gate, and `report`, the lines to print. Its
  `source` reads `plugin default` where it read `default`.

- a team `artifact` value no longer publishes a digest

  A team file that says `artifact` was honoured before. It is now ignored with
  a notice, and the shipped default applies, so a page from a repository that
  is not public, or a diff with a credential-shaped hunk, stays a local file.
  Set the `medium` option to `artifact` to publish such pages anyway.

### Removed

- `~/.claude/rendered-views.md`, `.claude/rendered-views.md` and
  `.claude/rendered-views.local.md` are no longer read

  Each gives one notice per project naming its value and where to set it
  instead: the `medium` option, `docs/conventions/rendered-views.yaml`, or
  `docs/conventions/rendered-views.local.yaml`.
