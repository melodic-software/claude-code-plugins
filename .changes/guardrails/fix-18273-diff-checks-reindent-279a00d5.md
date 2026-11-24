---
bump: patch
---

### Fixed

- Shared `check-lib.sh` synced where this plugin carries it: `checks_changed_lines` and `checks_added_ranges` take an opt-in `--skip-reindent`, which leaves out an added line equal, leading and trailing whitespace aside, to a line the same file's diff removes (a reindent, or a move within the file). Without it, every added line still counts.
- The pre-commit and pre-push content scans judge machine-specific paths with `--skip-reindent`, so a reindented line holding a pre-existing path passes, and still block one the change adds. Secret patterns, and every other guardrails check, still judge every added line, so a reindented line holding a secret blocks.
