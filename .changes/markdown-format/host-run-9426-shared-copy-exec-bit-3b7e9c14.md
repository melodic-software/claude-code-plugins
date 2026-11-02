---
bump: patch
---

### Fixed

- **A shared git-hook install stages every copy that starts with a shebang as `100755`.**
  `install.mjs copy --scope shared` staged the check lib and shebang assets at `100644` and wrote
  them `0644` on disk, which a consumer's hygiene check rejects. Copies with a shebang are now
  executable on disk and in the index, every other copy is `100644`, and a rerun repairs a copy
  whose exec bit is wrong
  ([#9426](https://github.com/melodic-software/claude-code-plugins/issues/9426)).
