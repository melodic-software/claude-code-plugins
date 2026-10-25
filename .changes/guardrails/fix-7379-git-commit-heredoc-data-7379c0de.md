---
bump: patch
---

### Fixed

- **block-root-delete-target:** a one-line `git commit -F - <<'EOF'` or `git tag -F - <<'EOF'` whose message names a root delete target is no longer refused: its quoted heredoc body is read as data, as for `cat` and `gh`. A git global option ahead of the subcommand (`git -c …`, `git -C …`), any other git subcommand or alias, `--file=-`, a `-F -` after `--` or in a prefix holding a quote or backslash, a pipe after the opener, and an opener on a later line are still scanned.
