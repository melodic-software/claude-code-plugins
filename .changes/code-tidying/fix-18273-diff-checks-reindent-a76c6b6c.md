---
bump: patch
---

### Fixed

- Shared `check-lib.sh` synced where this plugin carries it: `checks_changed_lines` and `checks_added_ranges` take an opt-in `--skip-reindent`, which leaves out an added line equal, leading and trailing whitespace aside, to a line the same file's diff removes (a reindent, or a move within the file). Without it, every added line still counts.
- The comment lint passes `--skip-reindent`, so it passes a pre-existing comment a formatter only reindented, and still fails a comment the change adds or rewords beside it.
