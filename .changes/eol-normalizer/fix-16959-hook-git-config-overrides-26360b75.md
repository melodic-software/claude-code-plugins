---
bump: patch
---

### Security

- The `git check-attr` call that reads a file's `eol` and `text` attributes passes `--no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null`, so it no longer starts the `core.fsmonitor` command a repository's own config names. `hook-utils.sh`'s repository-root lookups take the same overrides.
