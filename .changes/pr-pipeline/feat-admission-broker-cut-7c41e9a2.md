---
bump: minor
---

### Changed

- An issue whose Size, Complexity or Uncertainty field is empty, or was last set by an account that is neither a listed human nor the lanes App, is no longer refused with `not-assessed`: the field reads as Size `small`, Complexity `medium` or Uncertainty `known`, and the run goes ahead at that budget. The config check rejects an `issue-dimensions` table that lacks one of those keys, or whose `small` size is `split`.
- `report-outcome`'s resume pick still passes over a `not-assessed` marker an earlier run left, so a turn-capped issue resumes.

### Removed

- `not-assessed` as an issue-dimension skip: `report-skip` and the write file's `dimension-skip` input no longer accept it. fix-ci's neutral `not-assessed` check is unchanged.
- The `labeled-after` predicate key from `predicate.mjs`.
- The unused copy of `checkPatchRules` and its old refusal list in `resolve.mjs`; the live check is in `patch-rules.mjs`.
