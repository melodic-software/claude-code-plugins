---
bump: patch
---

### Changed

- **`audit`'s discovery script no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `discover.sh` matches each candidate method line with a here-string. The script does not set `pipefail`, so its output is unchanged; the rewrite only keeps it in the form the repository's pipefail gate requires.
