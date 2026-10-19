---
bump: minor
---

### Fixed

- `/harness-ops:plugins` sync no longer drops an install that moved during the run just because the CLI said it was already current. For each such id the script compares the post-run snapshot with the pre-mutation one: a different version is reported as `Moved during this run:` (a backward one also under `Downgraded:`), feeds the self-update note and the monitor reload advisory, and is split out of the divergence attribution as "moved during this run, cause unattributed". A version that cannot be read stays a no-op and shows as `Not verified:`. The digest gains `moved_during_run[]` and `noop_unverified`.
- The self-update note reads "<plugin> moved during this run", since this plugin's install can move through a concurrent update as well as the sweep.
- The sync spec's Concurrency section no longer calls a concurrent move indistinguishable from a no-op, and the skill's report contract and sync-context load rule account for the new row.
