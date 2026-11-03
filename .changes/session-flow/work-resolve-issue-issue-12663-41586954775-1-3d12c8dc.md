---
bump: minor
---

### Changed

- `workflow`: one stage order with the interview first. Stage 1 is now Interview (the Contract stage's work, renamed); Explore, Research and PRD become stages 2-4, conditional detours the interview calls when a question needs one. Stages 5-12 keep their numbers. The stage list, prose, checklist template, spec-first table and `retro`'s quick table all follow the new order (#12663).
- `workflow`: the stage definitions name the level each planning stage decides: the interview decides behavior, design decides interfaces and contracts, and plan decides files and symbols (#12663).
- `workflow`: between human stages (interview, PRD, design, plan) the continuation router suggests a handoff only at context-guard zone `dumb`; at `smart`, `acceptable` or `unknown` it compacts or continues (#12663).
- `workflow` tests: `test_workflow_continuation_rule.py` fails when the continuation context loses the `dumb`-zone handoff rule line.
