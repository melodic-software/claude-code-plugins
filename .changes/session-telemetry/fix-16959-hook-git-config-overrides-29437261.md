---
bump: patch
---

### Security

- Git commands in the plugin's `hooks/` scripts pass `--no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null`, so a repository's own `core.fsmonitor` command and git hooks no longer run when a hook checks whether a file is git-ignored or reads the repository's root, branch or files. Other commands a repository's config can name, such as a `.gitattributes` content filter, are not covered.
