---
bump: patch
---

### Changed

- The HIGH path floor rule says that adding only `disable-model-invocation: true` to a plugin skill's frontmatter that no agent could preload, and a non-script file under `plugins/<plugin>/evals/`, are exempt from the floor entries `babysit_risk.py` names; manifests, named files, declared paths and `denied-paths` still hold them.
