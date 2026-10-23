---
bump: minor
---

### Added

- [`/review:code-review`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/review/skills/code-review/SKILL.md)
  and [`/review:security-review`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/review/skills/security-review/SKILL.md)
  gain an Inputs section: they read the diff from the file on the wrapper's `FULL DIFF:` prompt
  line (and an incremental review's change from the file its `REVIEW SCOPE: incremental` note
  names), and the PR context from the file on the `PR CONTEXT:` line, so a lane that runs without
  Bash can review. With no diff line they use `gh pr diff` as before; with neither, they say the
  diff could not be read and review nothing. Security review now reads the PR context file as
  untrusted data.
- Both skills name those files in each `review:lane-verifier` brief, and the
  [lane-verifier](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/review/agents/lane-verifier.md)
  agent reads the diff from the file its brief names when it has no Bash.
- The `security-review-reads-named-diff-file` eval case.

### Changed

- Both skills follow the reporting mechanics the wrapper names, including an output schema, instead
  of assuming the inline-comment tool.
