---
bump: patch
---

### Changed

- The HIGH path floor rule says that adding only `disable-model-invocation: true` to a plugin skill's frontmatter that no agent could preload, and a non-script file under `plugins/<plugin>/evals/`, are exempt from the floor entries `babysit_risk.py` names; manifests, named files, declared paths and `denied-paths` still hold them.

- The HIGH path floor rule says a plugin or marketplace manifest leaves the floor and clears only when every key that differs is on its allow-lists (metadata such as `version` and `description`, a `userConfig` title or description, an added `userConfig` key with a default and no options); any other difference, a removed `version`, a new `plugin.json`, an added, removed or renamed marketplace entry, or a side that cannot be read or parsed scores HIGH as `manifest-review-required`.

- The HIGH path floor rule says a changed file in an eval case whose `case.yaml` could name a `scaffold_script`, or could not be read, scores HIGH as `eval-scaffold-review-required`.
