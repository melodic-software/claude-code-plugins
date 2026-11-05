---
bump: patch
---

### Fixed

- The unattended skill now copies `template.ps1` with `cat "${CLAUDE_SKILL_DIR}/template.ps1" > <target>.ps1` and then edits the copy, instead of an unspecified copy ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). A `cp` out of the plugin directory was denied in eval runs, and the agent then retyped the whole template with Write, which puts the library above `# STAGES`, safety functions included, at risk.

### Added

- Three unattended eval cases held out of the native suite now run: `una-author-elevated`, `una-guarded-drain` and `una-wsl-retire-guarded` ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Their `asks-approval` grader matches `una-preview-explained`'s, and `una-guarded-drain`'s `prove-waits` grader requires `Wait-ForState` as a statement inside `-Prove`, and its `predicate-non-empty` grader skips comment lines and nested blocks in the predicate and accepts a `-eq` count above zero.
