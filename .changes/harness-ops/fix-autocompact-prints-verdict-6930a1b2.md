---
bump: patch
---

### Fixed

- **behavior-probes reads a local slash command's output in a `prints` case.** Under `claude -p` the output arrives as a `<synthetic>` assistant message with a result of `num_turns` 0; the verdict now reads it instead of reporting `inconclusive` as a model turn. The `autocompact` area passed its first live run on Claude Code 2.1.312 (record 14).
