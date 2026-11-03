---
bump: major
---

### Changed

- `/planning:interview`: the 1:1 page reads its repository settings from the `interview_surface` mapping of `<home>/planning.yaml` and `<home>/planning.local.yaml`, resolved through the shared config cascade (ADR 0075), and the Settings tab names those layers `team` and `personal`. An invalid personal value leaves the team value standing. Reading them needs `node` on PATH. ([#12754](https://github.com/melodic-software/claude-code-plugins/issues/12754))

### Removed

- `.claude/interview-surface.json` is no longer read. While it exists, `ensure-running` prints one notice per data dir naming it and where its keys go, and prints it again after the file changes. Move its keys under `interview_surface:` in `docs/conventions/planning.yaml`. `displayName` is not a repository key there either.
