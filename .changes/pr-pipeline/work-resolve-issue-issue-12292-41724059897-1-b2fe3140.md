---
bump: patch
---

### Fixed

- The dispatchers' `budgetedFetch` (`request-budget.mjs`) resends a rate-limited read the way
  `createGitHub` does: after the reset, inside the read's 3 attempts and the rate latch's 60 s
  budget, and that refusal no longer fails the step. It counts and logs each request sent, a
  resend included. A write is still sent once, and a refusal it does not resend still fails the
  step unless the step holds (`API_BUDGET_HOLD=1`).
