---
bump: patch
---

### Fixed

- `/harness-ops:plugins sync all` under `install_new: all` no longer installs every catalog: the run stops before Step 4 as it does for `ask`, names the hold in `install_held: "all-target"`, and resumes only through the ask offer's `--only-install` re-entry; `/harness-ops:plugins-audit all` predicts the same stop.
- `/harness-ops:plugins sync` counts a project pin in a bare-layout linked worktree (`.bare/worktrees/<name>`) under linked worktrees, as `converge` does, instead of sending it to `converge`.
- `/harness-ops:plugins sync` and `/harness-ops:plugins-audit` digests now carry every field `scripts/digest-contract.json` declares, with its default when a run did not compute it, so a digest never omits a field.
- `/harness-ops:plugins converge` no longer lets a project pin keyed to a user home set the version it brings the other scopes to, as `sync` already did: `fleet-state.sh` now gives each divergence its `highest` version and each pin its `class`, and `sync` and `converge` both read them, so their divergence counts agree.
- `/harness-ops:plugins-audit` digests record each predicted install as an `installed[]` row, as they already did for enables, and every row for a CLI call carries its `label`, `rc`, `output` and `predicted`; the report prints the `would run:` line from that label.
- `/harness-ops:plugins` and `/harness-ops:plugins-audit` no longer restate every report row in their docs: the Report section keeps the rules for pasting the report, and the golden renders under `skills/plugins/scripts/fixtures/render/` are the record of each row's text.
- `/harness-ops:plugins sync` digests carry the user-settings normalizer's result as `normalize.status`, `moved`, `keys` and `reason` beside its raw `output`, and a refused reorder's `Action needed` bullet no longer repeats `refused:` before the reason.
