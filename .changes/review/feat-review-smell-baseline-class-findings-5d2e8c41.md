---
bump: minor
---

### Added

- `smell_baseline` setting (user option and `docs/conventions/review.yaml`): `default` keeps the
  `code-reviewer` agent's twelve-smell baseline, `off` turns the smell check off, and a
  repository-relative `.md` path points it at the repository's own list. A missing file falls back
  to the shipped baseline, and a change that edits `review.yaml` or the list file cannot choose
  its own list. The
  report names the list it used, and says so when it used the shipped baseline because the
  repository documents no standards.
- The baseline moves out of the agent into `reference/design-smells.md`, beside a catalog of the
  other twelve smells of *Refactoring*'s chapter 3; `/review:setup` offers both and writes the
  picked ones into the repository's own criteria, each write shown and confirmed.

### Changed

- `/review:code-review`, `/review:security-review` and the `lane-verifier` hunter name a finding's
  class and each place it occurs when the diff holds several of the same kind, so one fix covers
  every instance. `/review:quality-gate`'s review-fix rule and `/review:fanout fix`'s scope fence
  count every listed instance of a named class as part of the finding.
- Standards contract 1.1.5: planning and implementing skills also read `docs/review/README.md` when
  present and load only the rows the change touches.
