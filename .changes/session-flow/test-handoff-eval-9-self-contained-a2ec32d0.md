---
bump: patch
---

### Changed

- Handoff skill-eval case 9 (`purpose-argument-tailors-emphasis-only`) now ships the prior session state it assumes, as two synthetic fixtures under `evals/fixtures/` (the api-refactor work record and its draft endpoint design), and its prompt says that earlier work exists and names a working-directory memory dir when the run is outside a git work tree. Before, an empty eval sandbox left nothing to hand off, so runs refused or had their write denied instead of exercising the purpose argument. The expectations are unchanged.
