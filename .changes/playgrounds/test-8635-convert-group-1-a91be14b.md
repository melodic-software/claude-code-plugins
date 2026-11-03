---
bump: patch
---

### Changed

- The legacy `skills/use/evals/evals.json` cases moved to `evals/<case>/`: the installed, shadowed-name and cloud-delivery cases load a `playground` stand-in that carries a skill, so the present path runs, and the absent-install case is dropped as a duplicate of `use-absent-install-scope` ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
