---
bump: patch
---

### Changed

- `measure-invocation.sh score` reads a competitor's listing from `plugins/<plugin>/skills/<skill>`, derived from its `plugin:skill` id, so a probe file needs no `competitor_dirs` entry and holds no path into another plugin ([#9927](https://github.com/melodic-software/claude-code-plugins/issues/9927)). An explicit `competitor_dirs` entry still overrides the derived path, for a rival outside the `plugins/` tree; a competitor whose derived directory does not exist still fails the run. The seed probes drop their now-redundant entries.
