---
type: llm
focus: 'last_message'
---

The user asked what needs testing on a branch that changes several files (legacy plan 1 asked the same of "several files in the API app"). PASS only if the run matches the legacy expected output: "Analyzes git diff to classify changed files by test type needed. Generates a test plan with unit/integration/architecture/E2E sections. Identifies coverage gaps. Suggests /testing:write for gaps and /testing:run-e2e if UI/API changes exist." A section with nothing in it may be stated as empty or left out. FAIL if any other part is missing or contradicted.
