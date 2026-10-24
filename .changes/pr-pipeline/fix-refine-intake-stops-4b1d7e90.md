---
bump: minor
---

### Changed

- Intake refinement no longer stops an issue for a person on its own: a split of done-when items an unattended lane run cannot perform files no `needs-human` child issue, and lists those items in the refinement comment as checks a person runs while the rest of the done-when goes on; the lanes App refines each version of an issue body once instead of each issue once; an exact refinement that finds a duplicate or fixing change asks whether to close the issue instead of failing the run; and an issue edited while the model ran is triaged again instead of left waiting (`.github/scripts/intake-triage/refine.mjs`, `.github/workflows/intake-triage.yml`).
- work-unblock lifts the `needs-human` hold report-outcome put on an issue for a lanes App `Refs:` pull request when that pull request closes unmerged, not only when it merges, and hands the issue to triage (`.github/scripts/work-unblock/label-unblocked.mjs`).
