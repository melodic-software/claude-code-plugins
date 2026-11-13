---
bump: minor
---

### Changed

- Every corrector on the shared re-anchor method (`follow-our-standards`, `mind-your-maxims`, `pick-for-the-problem`, `point-dont-copy`, `reason-dont-recite`, `reuse-or-replace`, `script-the-deterministic-work`, `tighten-your-output`, `use-your-skills`) now reads the `verification` level. Under the default `light` (and `off`) it skips the method's step 2 confirmation and step 3 re-derivation subagents and reports `verification: skipped (<level>)`. Set `verification: standard` in `docs/conventions/discipline.yaml` on the default branch to keep them.
