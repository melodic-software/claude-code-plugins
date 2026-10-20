---
bump: patch
---

### Fixed

- `pre-commit-content` decides a file is binary from a NUL byte in its content, not from `--numstat`, and reads the range diff with `--text`, so a tracked `-diff` attribute (`*.yml -diff`) no longer turns the content scan off for a text file.
- `block-no-verify` allows `git config core.hooksPath .githooks` only at local scope and only while `.githooks/` holds the guardrails dispatcher; `--global`, `--system`, `--worktree` and `--file` are refused.
- `reference-verify` verifies a changed file whose name git quotes (`"`, `\` or a control byte) in full instead of skipping it.
- `block-no-verify` allows `git config core.hooksPath .githooks` only when `.githooks/` is a real directory and the dispatcher file it reads is a regular file, not a symlink, so a marker from outside the clone no longer counts.
- The shared git-hook check library drops a file whose content holds a NUL byte in its first 8000 bytes from the changed-line ranges, so `reference-verify` never reads binary content as changed lines.
