---
bump: major
---

### Removed

- **Breaking:** the `admission` and `work-classes` keys of `applies-when` are gone from the schema, so a `pr-pipeline.yaml` that still sets either fails validation; delete the key. No pipeline predicate reads a work class (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)): an issue with no class or any class, `work-class: structural` included, is decided by its labels, events and holds alone. resolve-issue's PR still carries `Hold: a human merges this` for an issue labeled `work-class: untrusted-provenance`, a trust hold that reads no other class.
