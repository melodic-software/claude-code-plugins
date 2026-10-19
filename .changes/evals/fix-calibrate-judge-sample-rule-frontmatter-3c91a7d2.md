---
bump: patch
---

### Fixed

- `calibrate-judge.py build` writes each sample into `case.yaml` as `execution.append_system_prompt` instead of `prompt.md` frontmatter, so a sample holding a markdown table rule (`---`) no longer ends the frontmatter early and its case loads and is tested.
