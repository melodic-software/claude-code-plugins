---
bump: minor
---

### Removed

- The babysit-prs verdict-evidence script's `evidence` command no longer takes `--answers-in`, `--answers-out`, `--answers-mode` or `--answers-only`, and no longer probes an answer key before its read: every call reads in full and prints the plain report, as it did without those flags.
