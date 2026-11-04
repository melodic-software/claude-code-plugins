---
bump: patch
---

### Changed

- The babysit-prs carry check (`babysit_merge_policy.CARRY_REFUSES`) also refuses to carry an approval past a push touching `plugins/evals/skills/plugin-eval/scripts/`, which the `eval-hill-climb.yml` gate workflows load (#12035).
