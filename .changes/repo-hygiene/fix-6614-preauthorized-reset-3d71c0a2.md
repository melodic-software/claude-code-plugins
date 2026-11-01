---
bump: patch
---

### Fixed

- `clean`'s confirmation gate now names permission granted up front in the request ("you have my OK", "do it without asking") as a general request that is not confirmation: the run still shows the dry run and asks, takes the answer only from a later user turn, never adds the acknowledgement prefix in the turn that carries the request, and never replaces the wrapper's `--apply` with an inline `git reset --hard` or `rm -rf`. An eval run given such a request had acknowledged its own guard and deleted local edits ([#6614](https://github.com/melodic-software/claude-code-plugins/issues/6614)).
