---
bump: patch
---

### Changed

- Six held `evals.json` cases join the `evals/` case suite with widened regex graders, pending an owner decision on #8635 ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)): `decompose-one-slice-per-behavior` and five `su-` cases (seeding the schedule, the first bind on skip, a populated schedule missing its label, the capability-tier backfill, and the personal-override ignore rule). Each widened pattern accepts a reply shape the first smoke showed the original rejecting.
