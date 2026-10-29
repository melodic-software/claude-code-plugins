---
bump: minor
---

### Added

- `merge.full-run-cap-bypass` (default `true`): pr-merge's `post-merge-dispatch` starts a full run of main inside its 30-minute cap when the post-merge check that judged (exit 0 or 5) lists an unverified lane merge with no dispatch run under way and main's run listing holds no non-cancelled run created at or after the merge on a commit that contains it. One run of main's tip covers the whole batch, and the next tick finds it in the listing, so the same batch never starts a second run. A run at a commit the job's checkout lacks counts as cover; a merge the checkout lacks, or one older than every listed run, is skipped. The lane arms nothing past `merge.max-in-flight` until a full run verifies the merges in flight, so a batch that landed inside the cap no longer waits it out. `false` keeps the cap for every merge, as before. `dispatch-full-run` (the push path) keeps the cap: it has no post-merge report and no history to judge coverage. The step reads files and the checkout only, so it makes no API call.
