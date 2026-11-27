---
bump: patch
---

### Fixed

- `/harness-ops:plugins sync all` under `install_new: all` no longer installs every catalog: the run stops before Step 4 as it does for `ask`, names the hold in `install_held: "all-target"`, and resumes only through the ask offer's `--only-install` re-entry; `/harness-ops:plugins-audit all` predicts the same stop.
- `/harness-ops:plugins sync` counts a project pin in a bare-layout linked worktree (`.bare/worktrees/<name>`) under linked worktrees, as `converge` does, instead of sending it to `converge`.
- `/harness-ops:plugins sync` and `/harness-ops:plugins-audit` digests now carry every field `scripts/digest-contract.json` declares, with its default when a run did not compute it, so a digest never omits a field.
