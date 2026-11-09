---
bump: patch
---

### Fixed

- **A prompt.md-only eval case now counts for `--require-evals`.** A plugin suite case with no `case.yaml`, whose `prompt.md` front matter tags the skill, satisfies the evals requirement, as the check's own rule says.
