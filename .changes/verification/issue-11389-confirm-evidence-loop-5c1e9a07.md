---
bump: minor
---

### Added

- `/verification:confirm` keeps an evidence loop per branch in
  `evidence-loop.<branch-slug>.json`, written atomically (a temporary file, then a rename). A
  `NEEDS WORK` verdict on a new head sends the gaps back to implementation, up to a cap of 3; at the
  cap no loop-back runs, the manifest says `Evidence loop: 3/3 cap reached, last NEEDS WORK`, and
  Next routes to the pull request so the pipeline's park-and-retry path takes over. The report and
  manifest carry an `Evidence loop:` line (`<k>/3` below the cap), and local evidence is kept for
  the last 3 heads of the branch
  ([#11389](https://github.com/melodic-software/claude-code-plugins/issues/11389)).
- The report and manifest carry a `Capture:` line with the capture status, its reason and its
  count. A capture that could not run is noted with its reason and never makes the verdict
  `NEEDS WORK` by itself.
- The fresh-context verifier reads the whole local evidence directory; `publishable` decides only
  what may be uploaded or pasted.

### Changed

- `/verification:confirm` takes touched features from `/app-control:drive affected` and no longer
  matches changed files against a control skill's `sources` globs. Without app-control the report
  says `touched features not matched (app-control not installed)` and nothing is refreshed. The
  `affected` diff covers committed changes only, so on a run with uncommitted changes the report
  says those files were not matched.
- The evidence manifest is written after every final verdict, not only when `/testing:run-e2e`
  ran.
- `/verification:confirm` passes `--unattended` to `/app-control:drive affected` and
  `/testing:run-e2e` when its own caller passed `--unattended`, so run-e2e writes the
  `e2e-summary.json` the capture status is read from.
