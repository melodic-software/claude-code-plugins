---
bump: patch
---

### Changed

- **`audit-comment-residue`'s detector no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `detect.sh` reads a file's first lines through process substitution when it looks for a generated-file marker. The script does not set `pipefail`, so its output is unchanged; the rewrite only keeps it in the form the repository's pipefail gate requires.
