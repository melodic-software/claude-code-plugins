---
bump: patch
---

### Fixed

- Scope pre-commit `format.sh` rewrites to hunks overlapping `checks_changed_lines` by running `markdownlint-cli2 --fix` in a temporary mirror, leaving untouched lines byte-identical and noting skipped untouched drift on stderr with exit 0 ([#19208](https://github.com/melodic-software/claude-code-plugins/issues/19208)).
