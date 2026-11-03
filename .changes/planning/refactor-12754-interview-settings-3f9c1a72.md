---
bump: major
---

### Changed

- the interview page reads its settings from planning's convention files

  The page server reads the `interview_page` mapping of `<home>/planning.yaml`
  (team) and `<home>/planning.local.yaml` (personal), under the convention home
  the repository binds, and the Settings tab names `team` or `personal` as the
  layer. The keys keep the names the Settings tab shows.

### Removed

- `.claude/interview-surface.json` is no longer read

  When it exists, `ensure-running` prints one notice per data dir naming each
  of its keys and where it goes now; none of its values apply.
