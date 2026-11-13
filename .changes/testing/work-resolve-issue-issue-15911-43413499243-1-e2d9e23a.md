---
bump: minor
---

### Changed

- `/testing:run-e2e` starts each entry point's expected outcome from the touched feature's stated
  results: each `## Drive` step's `Result:`, then the `**Proof.**` step's end state and the
  captures that show it. It then adds the change's requirement on top. Where the change alters
  what a step should produce, the requirement wins and the report names the stated result it
  replaced. On the drive route each step is judged against its stated result, the proof step's
  captures against its end state, and the whole run against the requirement. An entry point with
  no stated results is reported `no stated results` and is judged against the requirement alone.
  A failed drive's failure packet names both sources on its `Expected:` line.
