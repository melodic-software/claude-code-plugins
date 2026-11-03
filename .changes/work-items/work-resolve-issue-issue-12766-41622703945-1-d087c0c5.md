---
bump: patch
---

### Changed

- `reference/work-class-labels.md`, `reference/label-taxonomy.md`, `reference/item-content-trust.md` and triage's `SKILL.md` and `context/apply-outcome.md` no longer say a merge partition reads the `work-class:` label, because no merge step decides by a class other than `work-class: untrusted-provenance` (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)). They now say triage stamps the class as a record. Of the class and provenance labels, only `work-class: untrusted-provenance` and `provenance: signal` hold an item for a person.
