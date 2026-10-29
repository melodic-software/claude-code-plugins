---
bump: patch
---

### Added

- The `non-obvious-behavior-keying-behavior-present` eval case: the original case with the non-obvious-behavior keying heuristic stated in the prompt, run with `--ablation none`, so the pair discriminates when the variant passes `not-surface-only` and the original fails it. ([#10184](https://github.com/melodic-software/claude-code-plugins/issues/10184))

### Fixed

- The `non-obvious-behavior-keying` eval case drops its `skill-fired` grader: the prompt invokes the skill by its slash command, so firing is not in question, and the grader failed every with-plugin run of the [#3589](https://github.com/melodic-software/claude-code-plugins/issues/3589) discrimination run.
