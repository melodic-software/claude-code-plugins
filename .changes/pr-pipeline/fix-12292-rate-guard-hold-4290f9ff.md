---
bump: patch
---

### Fixed

- The shared rate guard (`rate-guard.mjs`) waits out a rate-limit reset that fits its 60 s budget
  (`SERVER_RETRY_BUDGET_MS`, resets summed per latch) and sends the call, instead of refusing it.
  `createGitHub` (`check-trusted-trigger.mjs`) sends a read a rate limit refused once more after
  the reset, inside its 3 attempts; a write is never resent. A reset past the budget is still
  refused.
- A step that holds (`API_BUDGET_HOLD=1`) gets a rate limit as a `::notice::` instead of an
  `::error::`: the Node guard leaves the exit to the caller instead of failing the step, and the
  `api-budget.bash` gh wrapper prints a notice. The call is still refused or returns 1, so a gate
  that does not hold, such as `ci-status` or the trusted-trigger check, still fails closed. No
  workflow sets the variable yet. A stop the job's stop file cannot take still fails the step.
