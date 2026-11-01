---
bump: patch
---

### Fixed

- The `animation-audit-readonly` eval case no longer lists Edit and Write in `allowed_tools`, which
  a case cannot grant itself. Its `no-write` and `no-edit` graders now read the trace for any write
  or edit call, or a Skill call with `--fix`, the same shape as `audit-launch-command-palette`, so
  they can still fail when those tools are absent.
- The `--fix` arm of the `no-write` grader in `animation-audit-readonly` and
  `audit-launch-command-palette` now matches only inside the Skill call's input, so a reply that
  offers `--fix` in text beside a bare audit call no longer fails it.
- The `motion-dropdown` and `motion-toast-stack` eval samples that used the drawer curve for an
  entrance now use the configured `out` curve, `cubic-bezier(0.23, 1, 0.32, 1)`. The graders are
  unchanged.
