---
bump: patch
---

### Fixed

- A hand dispatch of `pr-unblock.yml` with `activity: resolve-conflicts` on a mergeable pull
  request now merges the default branch tip into its head when the head is behind, through the
  same no-model clean-merge push a conflicting pull request gets, instead of skipping it as
  `not-applicable`. A head that already holds the tip is skipped as `up-to-date` and gets no
  check run. The draft, hold, protected-path, repeat-cap and lanes App identity gates are
  unchanged, and the dispatcher still sends only conflicting pull requests.
- `resolve-conflicts` skips a pull request whose base is not the default branch, such as a stacked
  layer, as `not-applicable`, so a hand dispatch never merges the default branch into it.
