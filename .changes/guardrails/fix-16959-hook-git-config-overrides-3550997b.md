---
bump: patch
---

### Security

- The hooks run every git command against a repository with `--no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null`, so a command named in that repository's own `.git/config`, such as `core.fsmonitor`, never runs when a hook checks whether a file is git-ignored or reads the repository's root, branch or files.
