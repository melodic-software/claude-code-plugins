---
bump: patch
---

### Changed

- **`/docs-naming:generate-file-name-gate` can now be invoked by the model** ([#8978](https://github.com/melodic-software/claude-code-plugins/issues/8978)). Before, `disable-model-invocation: true` kept it user-typed only. It only emits new files, refuses to overwrite without `--force` and commits nothing, so the invocation-mode grade (#7974) flipped it to `false`.
