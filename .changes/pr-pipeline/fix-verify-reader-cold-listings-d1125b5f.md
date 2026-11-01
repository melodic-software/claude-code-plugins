---
bump: patch
---

### Fixed

- The verdict reader's whole artifact listing refuses `verify:unreadable` after the first when its top-up holds more artifacts than GitHub's live count, or does not read, instead of paging two more. A listing that fails once it began a whole listing is noted beside the saved listing, so later readers in the same pr-merge, ci-status or dispatcher job refuse without paging again.
