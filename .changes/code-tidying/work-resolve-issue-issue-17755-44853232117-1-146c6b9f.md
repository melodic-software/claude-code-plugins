---
bump: patch
---

### Changed

- **Three skills no longer carry one stack's specifics.** `/code-tidying:audit-dead-code`'s evidence-pattern table describes each way code is reached without one language's idioms and drops its typical-language column. The skill now checks the registration conventions of the frameworks the candidate's own code uses. `/code-tidying:batch-simplify` groups files by the nearest build or package manifest without listing manifest names, and drops its shell-hook example. `/code-tidying:tidy-diff`'s generated-code residue cues describe each residue in plain terms instead of TypeScript and JavaScript syntax ([#17755](https://github.com/melodic-software/claude-code-plugins/issues/17755)).
