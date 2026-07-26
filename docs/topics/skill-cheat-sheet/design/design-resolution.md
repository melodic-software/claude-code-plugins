# Design resolution — skill-cheat-sheet (#1227)

outcome: early-exit (design resolved during `/planning:interview`, dual-validated)

The design-significant decisions for this work — data contract, grouping spine, generator shape,
location, audience posture — were resolved and locked during the interview stage and are recorded
in `../PLAN.md` `## Brief` (`### Constraints`, "Locked this interview"). Two independent
fresh-context reviewers (Fable + Opus) validated them; every accepted challenge was
evidence-verified in-session. Re-running `/planning:design` would re-derive the same threads.

Type/contract sketch (the one surface a design pass would own):

- **Contract:** `metadata` frontmatter field per the Agent Skills spec — flat string→string map,
  namespaced keys. This work adds `cheatsheet-*` keys (exact names + enums resolved by
  `/planning:plan`; vocabulary migrates into #1617's fleet convention).
- **Producer:** each in-scope `SKILL.md` (hand-authored values, swept once).
- **Consumers:** the new sheet generator (repo-side, reads the working tree); CI drift gate.
  No runtime consumer — keys are inert to installed plugins.
- **Precedent:** `discipline-batch` / `discipline-batch-rank` keys (production `metadata` usage).
