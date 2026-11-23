---
bump: none
---

Removes redundant `evals` eval cases: `ci-pin-models`, `design-criteria-first`, `invalid-gate-no-number`, `sandbox-refusal-windows`, `worktree-guard-stop`, `rules-not-a-target`, `measurable-criterion`, `price-before-running`. Each one's behavior is checked by a kept case, or its only
grader was an unlabeled judge, which counts as no evidence. No skill behavior changes.
