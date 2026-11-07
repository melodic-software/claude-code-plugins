---
bump: patch
---

### Changed

- Nine held `evals.json` cases join the `evals/` case suite with widened regex graders, pending an owner decision on #8635 ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)): `aq-flip-needs-no-class-label`, `decompose-one-slice-per-behavior`, `decompose-expand-contract-when-batches-land-green` and six `su-` cases (seeding the schedule, the first bind on skip, zero schedule rows, a populated schedule missing its label, the capability-tier backfill, and the personal-override ignore rule). Each widened pattern accepts a correct reply shape the original rejects.
