---
bump: minor
---

### Changed

- **The Brief keeps the interview's ADR verdict lines, and plan close-out checks they were posted.** An engineering Brief gains an optional `### ADR verdicts` section: one line per decision the interview's Decision record step saw, with its verdict, an overrule written as the final verdict. The interview page's restatement takes a matching `adrVerdicts` section, which `export-brief` writes above Deferred questions. `/planning:plan close-out` is done only when the pull request body and the linked issue's copy, read back after posting, hold every line of that section, so a decision that did not become an ADR keeps a durable record.
