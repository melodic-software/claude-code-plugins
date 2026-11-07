---
bump: patch
---

### Changed

- The setup, shape and structure `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Sixteen new cases cover setup's `check` and `apply` in a scaffolded repository (prerequisites and detect runs, key sources, the flow-mapping line, block-style writes, idempotent re-apply, a team-file comment aimed at the agent), shape's stage and evidence lines and its job order at the idea, existing and legacy stages, a research file carrying an instruction, a single job skipping the front door, structure's tree-test plan, its hand-off of look to `/user-interface:design` and navigation depth, and three cases where no skill should fire. `uc3-signup-first-success-flow` gains graders for the legacy expectation it did not yet grade. Legacy shape 6 and 9 were already covered by `team-file-degrade` and `quiet-ui-only`.
