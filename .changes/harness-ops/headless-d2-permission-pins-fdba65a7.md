---
bump: patch
---

### Fixed

- The `consume-restarts print-schedule` command prints `--permission-mode auto`, plus `--permission-prompts none` when the CLI is 2.1.259 or later, on every scheduled `claude -p` line, so the reader no longer inherits the user's `defaultMode`. Regenerate an existing schedule to pick this up.
