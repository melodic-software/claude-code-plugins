---
bump: patch
---

### Fixed

- cli-flag-verify treats a quoted argument as one argument: no word inside a quoted prompt (the prompt given to the print option, or a positional prompt) or a quoted flag value is read as a flag or a subcommand. The machine-health setup skill's scheduled prompt no longer reports its slash-command argument as an unknown Claude CLI flag.
- The reference-verify pre-push entry judges a pushed branch that merged the default branch only on the lines the branch itself adds, not on the lines the merge brought in, so a finding on the default branch no longer blocks every branch that merges it, and the push checks only the branch's own files.
