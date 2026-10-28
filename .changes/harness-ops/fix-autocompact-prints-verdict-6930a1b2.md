---
bump: patch
---

behavior-probes: a `prints` case now reads the output of a slash command that `claude -p` runs locally, which arrives as a `<synthetic>` assistant message with a result of `num_turns` 0, instead of reporting it `inconclusive` as a model turn. The `autocompact` area passed its first live run on Claude Code 2.1.312 (record 14).
