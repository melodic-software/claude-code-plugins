---
bump: patch
---

### Changed

- The generate skill's reference docs drop capital-letter emphasis, state the emit step's split
  rule for the HIGH bucket (split past 5 bullets; HIGH items past 7 move to MED), and describe the
  legal cluster with a generic case instead of one past trial.
- The HTML-to-PDF fallback reads the Playwright CLI's PDF command name and flags from its own help
  instead of restating them.
