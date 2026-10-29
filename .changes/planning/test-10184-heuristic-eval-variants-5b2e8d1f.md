---
bump: patch
---

### Added

- Three behavior-present eval cases, `disconnected-scan-before-new-work-behavior-present`, `observed-fact-evidence-bar-behavior-present` and `unilateral-decision-not-folded-behavior-present`, each its original case with the heuristic stated in the prompt and run with `--ablation none`, so a heuristic case discriminates when its variant passes the target grader and the original fails it. ([#10184](https://github.com/melodic-software/claude-code-plugins/issues/10184))

### Fixed

- The `unilateral-decision-not-folded` eval case now has a `scaffold.sh` that seeds a small webhook sender with a logger module, so its runs no longer find an empty repository and stop before planning.
