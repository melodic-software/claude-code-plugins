---
bump: patch
---

### Fixed

- `measure-invocation.sh emit-plugin-eval` now allows `Read`, `Glob` and `Grep` beside `Skill` in each emitted `prompt.md`, so an exploratory read is no longer a denial that marks the run INVALID. `reference/invocation-probes.md` notes that emitted runs need `--keep-temp` for the validity gate's trace checks ([#9457](https://github.com/melodic-software/claude-code-plugins/issues/9457)).
