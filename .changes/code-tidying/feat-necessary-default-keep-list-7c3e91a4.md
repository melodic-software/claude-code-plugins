---
bump: minor
---

### Changed

- **remove-comments defaults to `necessary` in every run.** `comment_posture: auto` now resolves to `necessary` whether or not `--pipeline` is passed, where it was `explanatory` outside the pull-request pipeline. Set `comment_posture: explanatory` (or pass the `explanatory` token) to keep the old interactive behavior; `none` stays selectable. `--pipeline` is still accepted and changes no setting.

### Added

- **A repository can replace what `necessary` keeps above the floor.** The new `comment_keep_list` setting (`userConfig`, the team file and the personal override) takes `default`, the shipped `skills/remove-comments/reference/keep-list.md`, or a repository-relative path to the repository's own criteria file, which replaces the shipped list. The floor stays under every list. `comment-reviewer` reads the resolved list, and a run names a non-shipped list in its report.
