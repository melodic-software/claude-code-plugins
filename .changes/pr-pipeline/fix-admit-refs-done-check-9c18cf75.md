---
bump: patch
---

### Fixed

- Intake admission and the work-unblock sweep no longer start the issue lane on an issue whose work a merged pull request may already have done. A pull request merged in this repository that names the issue on a `Refs:` line after its newest `**Decision recorded.**` or refinement comment parks the issue at `status: confirmed` with one admission comment naming the pull request, for an agent to close it or record what is left. Each admission pass reads its issues in one GraphQL call, and a failed read admits as before.
