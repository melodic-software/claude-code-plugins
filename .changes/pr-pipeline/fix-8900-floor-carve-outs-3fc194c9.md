---
bump: patch
---

### Changed

- The HIGH path floor rule says that adding only `disable-model-invocation: true` to a plugin skill's frontmatter that no agent could preload, and a non-script file under `plugins/<plugin>/evals/`, are exempt from the floor entries `babysit_risk.py` names; manifests, named files, declared paths and `denied-paths` still hold them.

- The HIGH path floor rule says a plugin or marketplace manifest leaves the floor, and scores HIGH as `manifest-review-required` only for a removed `userConfig` entry or changed default, an added or changed `options` enum, a changed code-running key, a changed marketplace `source`, or a side that cannot be read, parsed or has a repeated key.
