---
bump: minor
---

### Changed

- A size split that cannot be made posts its reason on the issue (codes `not-human`, `few-lines`, `no-split`, `bad-split`, `bad-subset`, `no-type`) instead of only a step summary, with no hold label. An issue with fewer than 2 trusted task-list lines gets the thin refinement first.

### Added

- A target-subset size split: sub-issues hold every trusted line plus a `Scope:` line naming verbatim targets. `admission-rules.json` `size-split` sets `on-decline` (`subset` or `park`) and `max-parts`.
- `models.issue-dimensions.split-child-size` (`medium`): a trusted size-split sub-issue rated Large runs at that size instead of skipping with `split-required`.
