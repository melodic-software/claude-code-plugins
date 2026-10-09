---
bump: minor
---

### Added

- **`/harness-ops:behavior-probes`: review-bot thread resolution and hook `updatedInput` cases.** Three `cases/auto-mode/` cases for a `gh api graphql` `resolveReviewThread` mutation on a review-bot thread in auto mode: with no `autoMode.allow` entry, with one conditioned on facts only tool output shows, and with an unconditional one (the control), each passed by `--settings`; `GH_HOST` points at an `.invalid` host, so no call reaches GitHub. Three `cases/hooks/` cases for a PreToolUse hook that returns `updatedInput` with no `permissionDecision`, rewriting a multi-line `git commit -m` to `git commit -F -`: in auto mode, in default mode with no allow rule, and in default mode with an allow rule that matches only the rewritten form.

### Fixed

- `probe.py run --dry-run` no longer skips cases past the live run ceiling of 20; `--max-runs` now defaults to 20 only under `--live`.
