---
bump: patch
---

### Changed

- Check 14 accepts a plugin suite case as a skill's evals: under `--require-evals`, a skill with no `evals/evals.json` passes when a case under its plugin's `evals/` tags it, in its `prompt.md` front matter (where the evals.json converter writes the tag) or in a single-file `case.yaml`. Converting a plugin's evals no longer fails the next change to one of its skills.
