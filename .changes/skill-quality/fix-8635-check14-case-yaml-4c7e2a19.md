---
bump: patch
---

### Changed

- Check 14 accepts a plugin suite case as a skill's evals: under `--require-evals`, a skill with no `evals/evals.json` passes when a `case.yaml` under its plugin's `evals/` has a `tags:` entry naming it, the tag the evals.json converter writes. Converting a plugin's evals no longer fails the next change to one of its skills.
