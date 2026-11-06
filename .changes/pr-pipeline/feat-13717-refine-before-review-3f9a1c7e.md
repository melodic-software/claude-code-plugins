---
bump: minor
---

### Added

- An activity's `stage: refine`, `order` and `group` make it a Refine pass, which `pr-refine`'s plan job starts from the PR's changed files; passes on disjoint files run in parallel, overlapping ones in order.
- `applies-when.paths-ignore`: changed paths these globs match never count toward `paths`. `fix-docs` ignores `.changes/**`, so a changelog fragment alone starts no fix.
- The README's stage order (build, refine, review, fix, verify, merge) and a Signals table.
