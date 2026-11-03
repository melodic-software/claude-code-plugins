---
bump: patch
---


### Fixed

- **The docs lookup removes its output directory.** The reading procedure's step 1 makes the
  `--out` directory with `mktemp -d`; it now tells the reader to remove that directory by its
  literal path when the lookup ends. Each lookup used to leave one `tmp.*` directory, up to
  1.2 MB, in the OS temp folder
  ([#9571](https://github.com/melodic-software/claude-code-plugins/issues/9571)).
