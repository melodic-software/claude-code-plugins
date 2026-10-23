---
bump: minor
---

### Changed

- `resolve-conflicts ci` runs no command and stages nothing: it reads the merge context the runner writes to `.lane/merge/` (each conflicted path's base, ours and theirs versions and both sides' history) in place of git, resolves each conflicted file in place, edits no other file, and leaves a path it cannot resolve with its conflict markers, which hands the run to a person ([`SKILL.md`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/source-control/skills/resolve-conflicts/SKILL.md#ci-mode)). The CI-mode evals follow: `resolve-conflicts-ci-mode-stages-resolved-paths` becomes `resolve-conflicts-ci-mode-resolves-in-place`.
