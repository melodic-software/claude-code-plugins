---
bump: major
---

### Removed

- `/testing:map-features`, `/testing:refresh-feature-map` and the plugin's `reference/feature-map.md`. An app's feature map is now its control skill, which `/app-control:map` writes (`create`), checks (`check`) and keeps current (`refresh`).
- The `feature_map_dir` key. `/testing:run-e2e` no longer resolves it, `/testing:setup apply` drops the line when it rewrites `docs/conventions/testing.yaml`, and the schema no longer lists it. A leftover line still never stops a test scan.

### Changed

- `/testing:run-e2e` reads the app's control skill (`.claude/skills/control-<app>/`) as its feature map: the hub's Ready replaces the doctor, before the first drive and after a failed step; the hub's driving tool replaces the recorded driver; `Attended runs only.` stops an unattended run. The per-entry-point report line is unchanged. A legacy testing-format map is not read: the run warns and names `/app-control:map refresh <path>`.

**Migration.** Run `/app-control:map refresh <path>` on each legacy map, at `.claude/skills/feature-map/` or wherever `feature_map_dir` pointed; it converts the map in its upkeep pull request. Then delete any `feature_map_dir` line. The scheduled `feature-map-upkeep` routine is now `control-skill-upkeep`, running `/app-control:map refresh`; its pull requests use `control-skill-upkeep/control-<slug>` branches, and open `feature-map-upkeep/*` branches are superseded (refresh lists them and adopts none). The first app-control refresh re-does every map, since no clean pass is recorded for a control skill yet.
