---
bump: patch
---

### Fixed

- `/harness-ops:plugins sync all` under `install_new: all` no longer installs every catalog: the run stops before Step 4 as it does for `ask`, names the hold in `install_held: "all-target"`, and resumes only through the ask offer's `--only-install` re-entry; `/harness-ops:plugins-audit all` predicts the same stop.
