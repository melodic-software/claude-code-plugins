---
bump: patch
---

### Fixed

- `pre-commit-content` decides a file is binary from a NUL byte in its content, not from `--numstat`, and reads the range diff with `--text`, so a tracked `-diff` attribute (`*.yml -diff`) no longer turns the content scan off for a text file.
- `block-no-verify` allows `git config core.hooksPath .githooks` only at local scope and only while `.githooks/` holds the guardrails dispatcher; `--global`, `--system`, `--worktree` and `--file` are refused.
- `reference-verify` verifies a changed file whose name git quotes (`"`, `\` or a control byte) in full instead of skipping it.
