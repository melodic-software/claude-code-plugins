---
bump: patch
---

### Added

- Shared eval fixtures under `evals/fixtures/`: the `tarnquill` (.NET) and `brackenfold` (Python) repositories from the eval scenario sources, and `seed.sh`, which seeds either one in the bare, conventions-only or converged state (or, for `tarnquill`, legacy) into a workspace and commits it on `main`. The fixture case `fx-seed-every-state` seeds all seven states and checks the conventions file each copy's `AGENTS.md` names. ([#9943](https://github.com/melodic-software/claude-code-plugins/issues/9943))
